#!/usr/bin/env bash

set -u
set -o pipefail

echo "=== 多代理 CA 自动安装 ==="

###############################################################################
# 配置区
###############################################################################

SYSTEM_CA_DIR="${SYSTEM_CA_DIR:-/usr/local/share/ca-certificates}"
CERT_PREFIX="${CERT_PREFIX:-proxy-ca}"

# openssl 连接超时时间，单位秒
OPENSSL_TIMEOUT="${OPENSSL_TIMEOUT:-20}"

# 默认只安装“自签名 CA”，也就是 subject == issuer 且 CA:TRUE 的证书
# 如果你的公司代理返回的是非自签名中间 CA，可以临时设置：
#   INSTALL_NON_SELF_SIGNED_CA=1 bash install_ca.sh
INSTALL_NON_SELF_SIGNED_CA="${INSTALL_NON_SELF_SIGNED_CA:-0}"

# 是否更新系统 CA
UPDATE_SYSTEM_CA="${UPDATE_SYSTEM_CA:-1}"

# 是否追加到 Python certifi
APPEND_CERTIFI="${APPEND_CERTIFI:-1}"

# 是否要求 root
REQUIRE_ROOT="${REQUIRE_ROOT:-1}"

DEFAULT_DOMAINS=(
  "huggingface.co"
  "hf.co"
  "www.modelscope.cn"
  "modelscope.cn"
  "pypi.org"
  "files.pythonhosted.org"
  "pypi.python.org"
  "github.com"
  "raw.githubusercontent.com"
  "gist.githubusercontent.com"
  "api.github.com"
  "developer.download.nvidia.com"
  "download.pytorch.org"
  "conda.anaconda.org"
  "repo.anaconda.com"
  "triton-ascend.osinfra.cn"
  "docker.io"
  "registry-1.docker.io"
  "auth.docker.io"
  "s3.amazonaws.com"
  "ec2.amazonaws.com"
  "d36fwf2c6r3z6y.cloudfront.net"
  "storage.googleapis.com"
  "googleapis.com"
  "cdn.jsdelivr.net"
  "unpkg.com"
  "archive.ubuntu.com"
  "security.ubuntu.com"
  "deb.debian.org"
  "packages.debian.org"
)

###############################################################################
# 基础检查
###############################################################################

if [[ "${REQUIRE_ROOT}" == "1" && "${EUID}" -ne 0 ]]; then
  echo "错误：请使用 root 权限运行，例如："
  echo "  sudo bash install_ca.sh"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "错误：未找到 openssl"
  exit 1
fi

if ! command -v awk >/dev/null 2>&1; then
  echo "错误：未找到 awk"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：未找到 python3"
  exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
  echo "错误：未找到 timeout 命令，请安装 coreutils"
  exit 1
fi

mkdir -p "${SYSTEM_CA_DIR}"

###############################################################################
# 工具函数
###############################################################################

get_proxy_env() {
  if [[ -n "${HTTPS_PROXY:-}" ]]; then
    printf '%s\n' "${HTTPS_PROXY}"
  elif [[ -n "${https_proxy:-}" ]]; then
    printf '%s\n' "${https_proxy}"
  elif [[ -n "${HTTP_PROXY:-}" ]]; then
    printf '%s\n' "${HTTP_PROXY}"
  elif [[ -n "${http_proxy:-}" ]]; then
    printf '%s\n' "${http_proxy}"
  else
    printf '\n'
  fi
}

parse_proxy() {
  local proxy_raw="$1"

  python3 - "$proxy_raw" <<'PY'
import sys
import shlex
import urllib.parse

raw = sys.argv[1].strip()

if not raw:
    items = {
        "PROXY_SCHEME": "",
        "PROXY_HOST": "",
        "PROXY_PORT": "",
        "PROXY_HOSTPORT": "",
        "PROXY_USER": "",
        "PROXY_PASS": "",
    }
else:
    if "://" not in raw:
        raw = "http://" + raw

    u = urllib.parse.urlsplit(raw)

    scheme = u.scheme or "http"
    host = u.hostname or ""
    port = str(u.port or "")
    user = urllib.parse.unquote(u.username or "")
    password = urllib.parse.unquote(u.password or "")

    if host and port:
        hostport = f"{host}:{port}"
    else:
        hostport = host

    items = {
        "PROXY_SCHEME": scheme,
        "PROXY_HOST": host,
        "PROXY_PORT": port,
        "PROXY_HOSTPORT": hostport,
        "PROXY_USER": user,
        "PROXY_PASS": password,
    }

for k, v in items.items():
    print(f"{k}={shlex.quote(v)}")
PY
}

openssl_supports_option() {
  local opt="$1"
  openssl s_client -help 2>&1 | grep -q -- "${opt}"
}

cert_fingerprint() {
  local cert="$1"

  openssl x509 \
    -in "${cert}" \
    -noout \
    -fingerprint \
    -sha256 2>/dev/null \
    | awk -F= '{print $2}' \
    | tr -d ':' \
    | tr '[:lower:]' '[:upper:]'
}

cert_subject() {
  local cert="$1"

  openssl x509 \
    -in "${cert}" \
    -noout \
    -subject \
    -nameopt RFC2253 2>/dev/null \
    | sed 's/^subject=//'
}

cert_issuer() {
  local cert="$1"

  openssl x509 \
    -in "${cert}" \
    -noout \
    -issuer \
    -nameopt RFC2253 2>/dev/null \
    | sed 's/^issuer=//'
}

cert_is_ca() {
  local cert="$1"

  openssl x509 -in "${cert}" -noout -text 2>/dev/null \
    | grep -q 'CA:TRUE'
}

cert_is_self_signed_ca() {
  local cert="$1"
  local subject
  local issuer

  cert_is_ca "${cert}" || return 1

  subject="$(cert_subject "${cert}")"
  issuer="$(cert_issuer "${cert}")"

  [[ -n "${subject}" && "${subject}" == "${issuer}" ]]
}

system_has_fingerprint() {
  local target_fp="$1"
  local f
  local fp

  shopt -s nullglob

  for f in "${SYSTEM_CA_DIR}"/*.crt "${SYSTEM_CA_DIR}"/*.pem; do
    [[ -f "${f}" ]] || continue

    fp="$(cert_fingerprint "${f}" || true)"

    if [[ "${fp}" == "${target_fp}" ]]; then
      return 0
    fi
  done

  return 1
}

split_pem_chain() {
  local input_file="$1"
  local output_dir="$2"

  mkdir -p "${output_dir}"
  rm -f "${output_dir}"/cert-*.pem "${output_dir}/count"

  awk -v dir="${output_dir}" '
    /-----BEGIN CERTIFICATE-----/ {
      n++
      in_cert = 1
      file = sprintf("%s/cert-%03d.pem", dir, n)
    }

    in_cert {
      print > file
    }

    /-----END CERTIFICATE-----/ {
      in_cert = 0
      close(file)
    }

    END {
      print n + 0 > (dir "/count")
    }
  ' "${input_file}"

  cat "${output_dir}/count" 2>/dev/null || echo 0
}

find_ca_candidates() {
  local chain_dir="$1"
  local pem

  shopt -s nullglob

  # 默认只找自签名 CA
  for pem in "${chain_dir}"/cert-*.pem; do
    [[ -f "${pem}" ]] || continue

    if cert_is_self_signed_ca "${pem}"; then
      printf '%s\n' "${pem}"
    fi
  done

  # 可选：允许非自签名 CA
  if [[ "${INSTALL_NON_SELF_SIGNED_CA}" == "1" ]]; then
    for pem in "${chain_dir}"/cert-*.pem; do
      [[ -f "${pem}" ]] || continue

      if cert_is_ca "${pem}" && ! cert_is_self_signed_ca "${pem}"; then
        printf '%s\n' "${pem}"
      fi
    done
  fi
}

extract_certs_by_openssl() {
  local domain="$1"
  local output_file="$2"
  local rc
  local cmd

  cmd=(
    timeout "${OPENSSL_TIMEOUT}"
    openssl s_client
    -connect "${domain}:443"
    -servername "${domain}"
    -showcerts
  )

  if [[ -n "${PROXY_HOSTPORT:-}" ]]; then
    if openssl_supports_option "-proxy"; then
      cmd+=(
        -proxy "${PROXY_HOSTPORT}"
      )

      if [[ -n "${PROXY_USER:-}" ]]; then
        if openssl_supports_option "-proxy_user" && openssl_supports_option "-proxy_pass"; then
          cmd+=(
            -proxy_user "${PROXY_USER}"
            -proxy_pass "${PROXY_PASS:-}"
          )
        else
          echo
          echo "警告：当前 openssl 不支持 -proxy_user/-proxy_pass，代理认证可能失败。"
        fi
      fi
    else
      echo
      echo "警告：当前 openssl 不支持 -proxy 参数，将尝试直连。"
    fi
  fi

  "${cmd[@]}" </dev/null >"${output_file}" 2>&1
  rc=$?

  return "${rc}"
}

certifi_path() {
  python3 - <<'PY' 2>/dev/null
try:
    import certifi
    print(certifi.where())
except Exception:
    pass
PY
}

certifi_has_fingerprint() {
  local certifi_file="$1"
  local target_fp="$2"
  local tmpdir
  local pem
  local fp

  [[ -f "${certifi_file}" ]] || return 1

  tmpdir="$(mktemp -d)"

  awk -v dir="${tmpdir}" '
    /-----BEGIN CERTIFICATE-----/ {
      n++
      in_cert = 1
      file = sprintf("%s/cert-%05d.pem", dir, n)
    }

    in_cert {
      print > file
    }

    /-----END CERTIFICATE-----/ {
      in_cert = 0
      close(file)
    }

    END {
      print n + 0 > (dir "/count")
    }
  ' "${certifi_file}"

  shopt -s nullglob

  for pem in "${tmpdir}"/cert-*.pem; do
    [[ -f "${pem}" ]] || continue

    fp="$(cert_fingerprint "${pem}" || true)"

    if [[ "${fp}" == "${target_fp}" ]]; then
      rm -rf "${tmpdir}"
      return 0
    fi
  done

  rm -rf "${tmpdir}"
  return 1
}

append_to_certifi_if_needed() {
  local cert="$1"
  local fp="$2"
  local certifi_file="$3"

  if certifi_has_fingerprint "${certifi_file}" "${fp}"; then
    echo "  certifi 已包含: ${fp}，跳过"
    return 1
  fi

  {
    echo
    echo "# ${CERT_PREFIX} ${fp}"
    cat "${cert}"
    echo
  } >> "${certifi_file}"

  echo "  已追加到 certifi: ${fp}"
  return 0
}

normalize_domain() {
  local d="$1"

  d="${d#http://}"
  d="${d#https://}"
  d="${d%%/*}"
  d="${d%%:*}"

  printf '%s\n' "${d}"
}

###############################################################################
# 解析代理
###############################################################################

PROXY_RAW="$(get_proxy_env)"
eval "$(parse_proxy "${PROXY_RAW}")"

if [[ -n "${PROXY_HOSTPORT:-}" ]]; then
  if [[ -n "${PROXY_USER:-}" ]]; then
    echo "HTTP_PROXY: ${PROXY_HOSTPORT}，认证用户: ${PROXY_USER}"
  else
    echo "HTTP_PROXY: ${PROXY_HOSTPORT}"
  fi
  echo "解析代理: ${PROXY_HOSTPORT}"
else
  echo "HTTP_PROXY: 未设置，将尝试直连"
fi

###############################################################################
# 处理域名列表
###############################################################################

RAW_DOMAINS=()

if [[ -n "${CA_DOMAINS:-}" ]]; then
  CA_DOMAINS_NORMALIZED="${CA_DOMAINS//,/ }"
  read -r -a RAW_DOMAINS <<< "${CA_DOMAINS_NORMALIZED}"
else
  RAW_DOMAINS=("${DEFAULT_DOMAINS[@]}")
fi

if [[ -n "${EXTRA_DOMAINS:-}" ]]; then
  EXTRA_DOMAINS_NORMALIZED="${EXTRA_DOMAINS//,/ }"
  read -r -a EXTRA_DOMAINS_ARRAY <<< "${EXTRA_DOMAINS_NORMALIZED}"
  RAW_DOMAINS+=("${EXTRA_DOMAINS_ARRAY[@]}")
fi

declare -A DOMAIN_SEEN=()
DOMAINS_LIST=()

for d in "${RAW_DOMAINS[@]}"; do
  nd="$(normalize_domain "${d}")"

  [[ -n "${nd}" ]] || continue

  if [[ -z "${DOMAIN_SEEN[${nd}]:-}" ]]; then
    DOMAIN_SEEN["${nd}"]=1
    DOMAINS_LIST+=("${nd}")
  fi
done

echo "检测域名数: ${#DOMAINS_LIST[@]}"

###############################################################################
# 主流程
###############################################################################

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

declare -A SEEN_CA_FP=()
declare -A DISCOVERED_CA_CERT=()

new_system_count=0
certifi_append_count=0

for domain in "${DOMAINS_LIST[@]}"; do
  printf '  [%s] 提取证书... ' "${domain}"

  safe_domain="${domain//[^A-Za-z0-9_.-]/_}"
  workdir="${TMP_ROOT}/${safe_domain}"
  mkdir -p "${workdir}"

  openssl_out="${workdir}/openssl.out"
  chain_dir="${workdir}/chain"

  extract_certs_by_openssl "${domain}" "${openssl_out}"
  rc=$?

  if [[ "${rc}" -ne 0 ]]; then
    echo "失败，openssl 退出码 ${rc}，跳过"
    continue
  fi

  cert_count="$(split_pem_chain "${openssl_out}" "${chain_dir}")"

  if [[ "${cert_count}" -eq 0 ]]; then
    echo "未提取到证书，跳过"
    continue
  fi

  mapfile -t ca_candidates < <(find_ca_candidates "${chain_dir}")

  if [[ "${#ca_candidates[@]}" -eq 0 ]]; then
    if [[ "${INSTALL_NON_SELF_SIGNED_CA}" == "1" ]]; then
      echo "未发现 CA 证书"
    else
      echo "未发现新自签名 CA"
    fi
    continue
  fi

  # 一般代理链里只需要安装一个根 CA。
  # 如果同一个域名返回多个候选 CA，这里取第一个。
  ca_file="${ca_candidates[0]}"

  fp="$(cert_fingerprint "${ca_file}" || true)"

  if [[ -z "${fp}" ]]; then
    echo "证书 fingerprint 解析失败，跳过"
    continue
  fi

  DISCOVERED_CA_CERT["${fp}"]="${ca_file}"

  if [[ -n "${SEEN_CA_FP[${fp}]:-}" ]]; then
    echo "CA 已安装，跳过"
    continue
  fi

  SEEN_CA_FP["${fp}"]=1

  if system_has_fingerprint "${fp}"; then
    echo "CA 已安装，跳过"
    continue
  fi

  subject="$(cert_subject "${ca_file}")"
  target="${SYSTEM_CA_DIR}/${CERT_PREFIX}-${fp}.crt"

  echo "发现新 CA: ${subject}"
  echo "    fingerprint: ${fp}"

  cp "${ca_file}" "${target}"
  chmod 0644 "${target}"

  echo "    ✓ 已安装到: ${target}"

  new_system_count=$((new_system_count + 1))
done

###############################################################################
# 更新系统 CA
###############################################################################

if [[ "${UPDATE_SYSTEM_CA}" == "1" ]]; then
  if [[ "${new_system_count}" -gt 0 ]]; then
    echo "更新系统 CA 库..."

    if command -v update-ca-certificates >/dev/null 2>&1; then
      if ! update-ca-certificates; then
        echo "警告：update-ca-certificates 执行失败"
      fi
    else
      echo "警告：未找到 update-ca-certificates，跳过系统 CA 更新"
    fi
  else
    echo "系统 CA 无新增，跳过 update-ca-certificates"
  fi
else
  echo "已禁用系统 CA 更新，跳过 update-ca-certificates"
fi

###############################################################################
# 追加到 Python certifi
###############################################################################

if [[ "${APPEND_CERTIFI}" == "1" ]]; then
  certifi_file="$(certifi_path || true)"

  if [[ -n "${certifi_file}" && -f "${certifi_file}" ]]; then
    if [[ "${#DISCOVERED_CA_CERT[@]}" -gt 0 ]]; then
      echo "追加 CA 到 certifi: ${certifi_file}"

      backup_file="${certifi_file}.bak.$(date +%Y%m%d%H%M%S)"
      cp "${certifi_file}" "${backup_file}" 2>/dev/null || true

      for fp in "${!DISCOVERED_CA_CERT[@]}"; do
        ca_file="${DISCOVERED_CA_CERT[${fp}]}"

        if append_to_certifi_if_needed "${ca_file}" "${fp}" "${certifi_file}"; then
          certifi_append_count=$((certifi_append_count + 1))
        fi
      done
    else
      echo "未发现代理 CA，跳过 certifi"
    fi
  else
    echo "未检测到 Python certifi，跳过 certifi"
  fi
else
  echo "已禁用 certifi 追加"
fi

echo "=== 完成：系统新增 ${new_system_count} 个代理 CA，certifi 新增 ${certifi_append_count} 个 ==="