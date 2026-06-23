#!/bin/bash
set -euo pipefail

# ========== 1. 解析 HTTP_PROXY 环境变量 ==========

url_decode() {
    local encoded="${1//+/ }"
    printf '%b' "${encoded//%/\\x}"
}

# 兼容 HTTPS_PROXY / HTTP_PROXY / https_proxy / http_proxy 几种常见写法
PROXY_RAW=""
PROXY_SRC=""
for v in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy; do
    val="${!v:-}"
    if [ -n "$val" ]; then
        PROXY_RAW="$val"
        PROXY_SRC="$v"
        break
    fi
done

if [ -z "$PROXY_RAW" ]; then
    echo "❌ 环境变量 HTTP_PROXY / http_proxy 均未设置，无法获取代理地址。"
    echo "   请先 export http_proxy=http://user:pass@proxy_ip:port 后重试。"
    exit 1
fi

# 去除协议前缀 http:// 或 https://
PROXY_URL="${PROXY_RAW#http://}"
PROXY_URL="${PROXY_URL#https://}"

# 去除末尾斜杠
PROXY_URL="${PROXY_URL%/}"

PROXY_USER=""
PROXY_PASS=""
PROXY_AUTH=""

# 判断是否包含用户名密码：user:pass@host:port
if [[ "$PROXY_URL" == *"@"* ]]; then
    # 使用最后一个 @ 作为认证信息和地址的分隔符
    # 这样可以降低密码中包含 @ 的情况造成的问题，
    # 但更推荐密码中的 @ 使用 %40 编码。
    PROXY_AUTH="${PROXY_URL%@*}"
    PROXY_ADDR="${PROXY_URL##*@}"

    if [[ "$PROXY_AUTH" != *":"* ]]; then
        echo "❌ ${PROXY_SRC} 中包含认证信息，但格式不是 user:pass@host:port。"
        echo "   当前 ${PROXY_SRC}='${PROXY_RAW}'"
        exit 1
    fi

    PROXY_USER="${PROXY_AUTH%%:*}"
    PROXY_PASS="${PROXY_AUTH#*:}"

    PROXY_USER="$(url_decode "$PROXY_USER")"
    PROXY_PASS="$(url_decode "$PROXY_PASS")"

    if [ -z "$PROXY_USER" ] || [ -z "$PROXY_PASS" ]; then
        echo "❌ 无法从 ${PROXY_SRC} 中解析出代理用户名或密码。"
        echo "   当前 ${PROXY_SRC}='${PROXY_RAW}'"
        exit 1
    fi
else
    PROXY_ADDR="$PROXY_URL"
fi

# 去除地址末尾可能残留的路径
PROXY_ADDR="${PROXY_ADDR%%/*}"

# 分离主机和端口；若未显式给出端口，按协议默认 80/443
if [[ "$PROXY_ADDR" == *:* ]]; then
    PROXY_HOST="${PROXY_ADDR%:*}"
    PROXY_PORT="${PROXY_ADDR##*:}"
else
    PROXY_HOST="$PROXY_ADDR"
    if [[ "$PROXY_RAW" == https://* ]]; then
        PROXY_PORT="443"
    else
        PROXY_PORT="80"
    fi
    echo "⚠️ ${PROXY_SRC} 未指定端口，默认使用 ${PROXY_PORT}。"
fi

if [ -z "$PROXY_HOST" ] || [ -z "$PROXY_PORT" ]; then
    echo "❌ 无法从 ${PROXY_SRC}='${PROXY_RAW}' 解析出主机和端口。"
    exit 1
fi

# 构造 openssl s_client 代理参数
OPENSSL_PROXY_ARGS=(-proxy "${PROXY_HOST}:${PROXY_PORT}")

if [ -n "$PROXY_USER" ]; then
    OPENSSL_PROXY_ARGS+=(-proxy_user "$PROXY_USER" -proxy_pass "pass:${PROXY_PASS}")
fi

# 为 apt/yum/dnf 构造代理 URL（沿用传入的 http_proxy，认证信息保持原始 URL 编码）
# 统一用 http:// 前缀：代理本身用 HTTP CONNECT，scheme 指的是到代理的连接，不影响目标站点的 https。
if [ -n "$PROXY_AUTH" ]; then
    PKG_PROXY_URL="http://${PROXY_AUTH}@${PROXY_HOST}:${PROXY_PORT}"
else
    PKG_PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
fi

# 打印代理信息，避免泄露密码
echo "=== 多代理 CA 自动安装 ==="

if [ -n "$PROXY_USER" ]; then
    echo "${PROXY_SRC}: ${PROXY_HOST}:${PROXY_PORT}，认证用户: ${PROXY_USER}"
else
    echo "${PROXY_SRC}: ${PROXY_HOST}:${PROXY_PORT}，无认证"
fi

echo "解析代理:  ${PROXY_HOST}:${PROXY_PORT}"

# ========== 1.5 自动安装缺失的必备工具 ==========
# 通过命令行参数给 apt/yum/dnf 配置代理（沿用上面解析出的 PKG_PROXY_URL），
# 不依赖也不修改全局配置文件。
# 注意 bootstrap 困境：若代理是 TLS 拦截型，CA 尚未安装时 https 源会校验失败，
# 因此安装这批工具时临时关闭包管理器的 SSL 校验（仅此一步）。

# 探测包管理器
PKG_MGR=""
for m in apt-get dnf yum; do
    if command -v "$m" >/dev/null 2>&1; then
        PKG_MGR="$m"
        break
    fi
done

# 安装一个或多个包，返回安装命令的退出码
pkg_install() {
    case "$PKG_MGR" in
        apt-get)
            DEBIAN_FRONTEND=noninteractive apt-get update \
                -o Acquire::http::Proxy="$PKG_PROXY_URL" \
                -o Acquire::https::Proxy="$PKG_PROXY_URL" \
                -o Acquire::https::Verify-Peer=false >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                -o Acquire::http::Proxy="$PKG_PROXY_URL" \
                -o Acquire::https::Proxy="$PKG_PROXY_URL" \
                -o Acquire::https::Verify-Peer=false \
                "$@"
            ;;
        dnf|yum)
            "$PKG_MGR" install -y \
                --setopt=proxy="$PKG_PROXY_URL" \
                --setopt=sslverify=0 \
                "$@"
            ;;
        *)
            return 1
            ;;
    esac
}

# 确保某命令存在，缺失则尝试安装对应的包
ensure_tool() {
    local cmd="$1"; shift
    local pkgs=("$@")
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    if [ -z "$PKG_MGR" ]; then
        echo "⚠️ 缺少 ${cmd}，且未找到 apt/yum/dnf，无法自动安装。"
        return 1
    fi
    echo "缺少 ${cmd}，尝试用 ${PKG_MGR} 安装：${pkgs[*]} ..."
    if pkg_install "${pkgs[@]}" >/tmp/pkg-install.log 2>&1; then
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  ✓ ${cmd} 安装成功"
            return 0
        fi
    fi
    echo "  ❌ ${cmd} 安装失败，详见 /tmp/pkg-install.log（末尾几行）："
    tail -n 5 /tmp/pkg-install.log 2>/dev/null | sed 's/^/      /'
    return 1
}

if [ -n "$PKG_MGR" ]; then
    echo "包管理器: ${PKG_MGR}，代理: ${PROXY_HOST}:${PROXY_PORT}"
fi

# openssl 命令行：CA 提取的核心依赖（部分精简镜像只有 openssl-libs）
ensure_tool openssl openssl || true

# ca-certificates：提供系统信任库目录与 update-ca-* 命令（Debian 是 update-ca-certificates，
# RHEL 是 update-ca-trust）。两者都没有时才安装一次。
if ! command -v update-ca-certificates >/dev/null 2>&1 \
   && ! command -v update-ca-trust >/dev/null 2>&1 \
   && [ -n "$PKG_MGR" ]; then
    echo "缺少 update-ca-* 命令，尝试用 ${PKG_MGR} 安装 ca-certificates ..."
    if pkg_install ca-certificates >/tmp/pkg-install.log 2>&1; then
        echo "  ✓ ca-certificates 安装完成"
    else
        echo "  ⚠️ ca-certificates 安装失败，详见 /tmp/pkg-install.log（末尾几行）："
        tail -n 5 /tmp/pkg-install.log 2>/dev/null | sed 's/^/      /'
    fi
fi

# 检测 openssl s_client 的代理能力（CentOS 7/8 自带的 openssl 版本较老）
#   OpenSSL < 1.1.0（如 CentOS 7 的 1.0.2）: 完全不支持 -proxy
#   OpenSSL 1.1.x（如 RHEL/Rocky/Alma 8 的 1.1.1）: 支持 -proxy，但不支持 -proxy_user/-proxy_pass
#   OpenSSL >= 3.0（如 RHEL 9 / CentOS Stream 9）: 全部支持
if ! command -v openssl >/dev/null 2>&1; then
    echo "❌ 未找到 openssl 命令行工具，且自动安装失败。"
    echo "   请手动安装后重试：  apt-get install -y openssl  或  yum install -y openssl"
    exit 1
fi

OPENSSL_SCLIENT_HELP="$(openssl s_client -help 2>&1 || true)"

if ! grep -qE '(^|[[:space:]])-proxy([[:space:]]|$)' <<<"$OPENSSL_SCLIENT_HELP"; then
    echo "❌ 当前 openssl 的 s_client 不支持 -proxy 选项（需 OpenSSL ≥ 1.1.0）。"
    echo "   CentOS 7 自带 OpenSSL 1.0.2，请先升级 openssl 后重试。"
    echo "   当前版本: $(openssl version 2>/dev/null || echo unknown)"
    exit 1
fi

if [ -n "$PROXY_USER" ] && ! grep -q -- '-proxy_user' <<<"$OPENSSL_SCLIENT_HELP"; then
    echo "⚠️ 当前 openssl 不支持 -proxy_user/-proxy_pass（需 OpenSSL ≥ 3.0），将以无认证方式连接代理。"
    echo "   若代理要求认证可能导致提取失败。当前版本: $(openssl version 2>/dev/null || echo unknown)"
    OPENSSL_PROXY_ARGS=(-proxy "${PROXY_HOST}:${PROXY_PORT}")
fi

# ========== 2. 获取域名列表 ==========

# 把命令行参数（可能是完整 URL）规范化成纯主机名
normalize_domain() {
    local d="$1"
    # 去除协议前缀
    d="${d#http://}"
    d="${d#https://}"
    # 去除可能存在的 user:pass@
    d="${d##*@}"
    # 去除路径 / 查询 / 片段
    d="${d%%/*}"
    d="${d%%\?*}"
    d="${d%%#*}"
    # 去除端口
    d="${d%%:*}"
    # 去除首尾空白
    d="${d#"${d%%[![:space:]]*}"}"
    d="${d%"${d##*[![:space:]]}"}"
    printf '%s' "$d"
}

DOMAINS=()
if [ "$#" -gt 0 ]; then
    for raw in "$@"; do
        norm="$(normalize_domain "$raw")"
        if [ -n "$norm" ]; then
            DOMAINS+=("$norm")
        else
            echo "⚠️ 忽略无效参数: '${raw}'"
        fi
    done
fi

if [ ${#DOMAINS[@]} -eq 0 ]; then
    # 内置 AI 开发常用域名列表
    DOMAINS=(
        # AI 模型与数据集
        huggingface.co
        hf.co
        www.modelscope.cn
        modelscope.cn

        # Python 包管理
        pypi.org
        files.pythonhosted.org
        pypi.python.org

        # 代码仓库
        github.com
        raw.githubusercontent.com
        gist.githubusercontent.com
        api.github.com

        # 深度学习框架与工具
        developer.download.nvidia.com
        download.pytorch.org
        conda.anaconda.org
        repo.anaconda.com
        triton-ascend.osinfra.cn

        # 容器镜像
        docker.io
        registry-1.docker.io
        auth.docker.io

        # 云服务
        s3.amazonaws.com
        ec2.amazonaws.com
        d36fwf2c6r3z6y.cloudfront.net
        storage.googleapis.com
        googleapis.com

        # 常用 CDN / 数据
        cdn.jsdelivr.net
        unpkg.com

        # 系统源，构建镜像常用
        archive.ubuntu.com
        security.ubuntu.com
        deb.debian.org
        packages.debian.org
    )
fi

echo "检测域名数: ${#DOMAINS[@]}"

# ========== 3. 工具函数与状态初始化 ==========

# 根据系统选择 CA 信任目录与更新命令
#   Debian/Ubuntu: /usr/local/share/ca-certificates + update-ca-certificates
#   RHEL/CentOS/Fedora/openEuler: /etc/pki/ca-trust/source/anchors + update-ca-trust
# 关键点：RHEL 系的 update-ca-trust 只扫描 anchors 目录，证书放到 Debian 路径会被忽略，
# 导致"安装成功"但系统仍不信任。
if command -v update-ca-trust >/dev/null 2>&1 && [ -d /etc/pki/ca-trust/source/anchors ]; then
    CA_DIR="/etc/pki/ca-trust/source/anchors"
    CA_UPDATE_CMD="update-ca-trust"
elif command -v update-ca-certificates >/dev/null 2>&1; then
    CA_DIR="/usr/local/share/ca-certificates"
    CA_UPDATE_CMD="update-ca-certificates"
elif [ -d /etc/pki/ca-trust/source/anchors ]; then
    # update-ca-trust 不在 PATH 但目录存在（极少数精简镜像）
    CA_DIR="/etc/pki/ca-trust/source/anchors"
    CA_UPDATE_CMD="update-ca-trust"
else
    # 兜底：默认 Debian 布局
    CA_DIR="/usr/local/share/ca-certificates"
    CA_UPDATE_CMD=""
fi
mkdir -p "$CA_DIR"
echo "CA 信任目录: ${CA_DIR}（更新命令: ${CA_UPDATE_CMD:-未找到}）"

# 提取证书 SHA-256 指纹（去掉冒号，统一大写）
cert_fingerprint() {
    local cert="$1"
    openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null \
        | awk -F= 'NF>1{print $2}' \
        | tr -d ':' \
        | tr '[:lower:]' '[:upper:]' \
        || true
}

# 清理本次运行的临时文件
rm -f /tmp/all_certs.pem /tmp/cert-*.pem /tmp/fingerprints.txt /tmp/certifi-check-*.pem 2>/dev/null || true
touch /tmp/fingerprints.txt

# 预扫描已安装的代理 CA，把指纹写入跟踪文件，避免重复安装
PRELOADED_COUNT=0
shopt -s nullglob
for existing in "$CA_DIR"/proxy-ca-*.crt; do
    fp="$(cert_fingerprint "$existing")"
    [ -n "$fp" ] || continue
    if ! grep -qx "$fp" /tmp/fingerprints.txt 2>/dev/null; then
        echo "$fp" >> /tmp/fingerprints.txt
        PRELOADED_COUNT=$((PRELOADED_COUNT + 1))
    fi
done
shopt -u nullglob

if [ "$PRELOADED_COUNT" -gt 0 ]; then
    echo "已检测到 ${PRELOADED_COUNT} 个先前安装的代理 CA，将跳过同指纹证书。"
fi

INSTALLED_COUNT=0

# ========== 4. 遍历域名提取 CA ==========

for DOMAIN in "${DOMAINS[@]}"; do
    echo -n "  [${DOMAIN}] 提取证书... "
    set +o pipefail
    timeout 8 openssl s_client \
        "${OPENSSL_PROXY_ARGS[@]}" \
        -connect "${DOMAIN}:443" \
        -showcerts </dev/null 2>/dev/null | \
        sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/all_certs.pem
    OPENSSL_EXIT="${PIPESTATUS[0]}"
    set -o pipefail

    if [ "$OPENSSL_EXIT" -ne 0 ]; then
        echo "失败，openssl 退出码 ${OPENSSL_EXIT}，跳过"
        continue
    fi

    if [ ! -s /tmp/all_certs.pem ]; then
        echo "失败，未获取到证书，跳过"
        continue
    fi

    # 分离证书
    rm -f /tmp/cert-*.pem

    awk '
        /-----BEGIN CERTIFICATE-----/ {
            n++;
            f=sprintf("/tmp/cert-%02d.pem", n-1)
        }
        {
            if (f) print > f
        }
    ' /tmp/all_certs.pem

    FOUND_NEW_CA=0
    SKIPPED_CA=0

    for cert in /tmp/cert-*.pem; do
        [ -f "$cert" ] || continue

        subject="$(openssl x509 -in "$cert" -noout -subject 2>/dev/null | sed 's/^subject=//')"
        issuer="$(openssl x509 -in "$cert" -noout -issuer 2>/dev/null | sed 's/^issuer=//')"

        if [ "$subject" = "$issuer" ] && [ -n "$subject" ]; then
            fingerprint="$(cert_fingerprint "$cert")"

            if [ -z "$fingerprint" ]; then
                continue
            fi

            if grep -qx "$fingerprint" /tmp/fingerprints.txt 2>/dev/null; then
                SKIPPED_CA=1
                continue
            fi

            echo ""
            echo "    发现新 CA: $subject"

            cp "$cert" "${CA_DIR}/proxy-ca-${fingerprint}.crt"

            echo "$fingerprint" >> /tmp/fingerprints.txt

            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            FOUND_NEW_CA=1
        fi
    done

    if [ "$FOUND_NEW_CA" -eq 1 ]; then
        echo "  ✓ 已安装"
    elif [ "$SKIPPED_CA" -eq 1 ]; then
        echo "CA 已安装，跳过"
    else
        echo "未发现新自签名 CA"
    fi
done

# ========== 5. 更新系统信任库 ==========

if [ "$INSTALLED_COUNT" -gt 0 ]; then
    echo "更新系统 CA 库..."
    if [ -n "$CA_UPDATE_CMD" ] && command -v "$CA_UPDATE_CMD" >/dev/null 2>&1; then
        if [ "$CA_UPDATE_CMD" = "update-ca-trust" ]; then
            update-ca-trust extract
        else
            update-ca-certificates
        fi
    else
        echo "未找到 CA 更新命令，请手动安装 ca-certificates（Debian）或 ca-certificates + update-ca-trust（RHEL/CentOS）"
    fi
else
    echo "系统 CA 无新增，跳过更新。"
fi

# ========== 6. 追加到 Python certifi，如果存在 ==========

CERTIFI_APPENDED=0

if command -v python3 &>/dev/null; then
    CERTIFI_PATH="$(
        python3 -c "import certifi; print(certifi.where())" 2>/dev/null || true
    )"

    if [ -n "$CERTIFI_PATH" ] && [ -f "$CERTIFI_PATH" ]; then
        # 把 certifi 拆分成单证书文件，构建已存在指纹集合
        rm -f /tmp/certifi-check-*.pem 2>/dev/null || true

        awk '
            /-----BEGIN CERTIFICATE-----/ {
                n++;
                f=sprintf("/tmp/certifi-check-%05d.pem", n)
            }
            {
                if (f) print > f
            }
            /-----END CERTIFICATE-----/ {
                if (f) close(f);
                f=""
            }
        ' "$CERTIFI_PATH"

        : > /tmp/certifi-fingerprints.txt
        shopt -s nullglob
        for existing_cert in /tmp/certifi-check-*.pem; do
            efp="$(cert_fingerprint "$existing_cert")"
            [ -n "$efp" ] || continue
            echo "$efp" >> /tmp/certifi-fingerprints.txt
        done
        shopt -u nullglob

        CERTIFI_HEADER_PRINTED=0

        shopt -s nullglob
        for crt in "${CA_DIR}"/proxy-ca-*.crt; do
            [ -f "$crt" ] || continue

            CRT_FINGERPRINT="$(cert_fingerprint "$crt")"
            if [ -z "$CRT_FINGERPRINT" ]; then
                continue
            fi

            if grep -qx "$CRT_FINGERPRINT" /tmp/certifi-fingerprints.txt 2>/dev/null; then
                continue
            fi

            if [ "$CERTIFI_HEADER_PRINTED" -eq 0 ]; then
                echo "追加 CA 到 certifi: ${CERTIFI_PATH}"
                CERTIFI_HEADER_PRINTED=1
            fi

            {
                echo ""
                echo "# proxy-ca ${CRT_FINGERPRINT}"
                cat "$crt"
            } >> "$CERTIFI_PATH"

            echo "$CRT_FINGERPRINT" >> /tmp/certifi-fingerprints.txt
            echo "  已追加到 certifi: ${CRT_FINGERPRINT}"
            CERTIFI_APPENDED=$((CERTIFI_APPENDED + 1))
        done
        shopt -u nullglob

        if [ "$CERTIFI_HEADER_PRINTED" -eq 0 ]; then
            echo "certifi 已包含全部代理 CA，无需追加。"
        fi
    else
        echo "未检测到 Python certifi，跳过。"
    fi
fi

# ========== 7. 清理临时文件 ==========

rm -f /tmp/all_certs.pem /tmp/cert-*.pem /tmp/fingerprints.txt \
      /tmp/certifi-check-*.pem /tmp/certifi-fingerprints.txt 2>/dev/null || true

TOTAL_SYSTEM_CA=0
shopt -s nullglob
for crt in "${CA_DIR}"/proxy-ca-*.crt; do
    TOTAL_SYSTEM_CA=$((TOTAL_SYSTEM_CA + 1))
done
shopt -u nullglob

echo "=== 完成：本次新增系统 CA ${INSTALLED_COUNT} 个（共 ${TOTAL_SYSTEM_CA} 个），certifi 新增 ${CERTIFI_APPENDED} 个 ==="
