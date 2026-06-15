#!/bin/bash
set -euo pipefail

# ========== 1. 解析 HTTP_PROXY 环境变量 ==========

url_decode() {
    local encoded="${1//+/ }"
    printf '%b' "${encoded//%/\\x}"
}

if [ -z "${HTTP_PROXY:-}" ]; then
    echo "❌ 环境变量 HTTP_PROXY 未设置，无法获取代理地址。"
    echo "   请在 Dockerfile 中设置 ENV HTTP_PROXY=http://proxy_ip:port 后重试。"
    exit 1
fi

# 去除协议前缀 http:// 或 https://
PROXY_URL="${HTTP_PROXY#http://}"
PROXY_URL="${PROXY_URL#https://}"

# 去除末尾斜杠
PROXY_URL="${PROXY_URL%/}"

PROXY_USER=""
PROXY_PASS=""

# 判断是否包含用户名密码：user:pass@host:port
if [[ "$PROXY_URL" == *"@"* ]]; then
    # 使用最后一个 @ 作为认证信息和地址的分隔符
    # 这样可以降低密码中包含 @ 的情况造成的问题，
    # 但更推荐密码中的 @ 使用 %40 编码。
    PROXY_AUTH="${PROXY_URL%@*}"
    PROXY_ADDR="${PROXY_URL##*@}"

    if [[ "$PROXY_AUTH" != *":"* ]]; then
        echo "❌ HTTP_PROXY 中包含认证信息，但格式不是 user:pass@host:port。"
        echo "   当前 HTTP_PROXY='${HTTP_PROXY}'"
        exit 1
    fi

    PROXY_USER="${PROXY_AUTH%%:*}"
    PROXY_PASS="${PROXY_AUTH#*:}"

    PROXY_USER="$(url_decode "$PROXY_USER")"
    PROXY_PASS="$(url_decode "$PROXY_PASS")"

    if [ -z "$PROXY_USER" ] || [ -z "$PROXY_PASS" ]; then
        echo "❌ 无法从 HTTP_PROXY 中解析出代理用户名或密码。"
        echo "   当前 HTTP_PROXY='${HTTP_PROXY}'"
        exit 1
    fi
else
    PROXY_ADDR="$PROXY_URL"
fi

# 分离主机和端口
PROXY_HOST="${PROXY_ADDR%:*}"
PROXY_PORT="${PROXY_ADDR##*:}"

if [ -z "$PROXY_HOST" ] || [ -z "$PROXY_PORT" ] || [ "$PROXY_HOST" = "$PROXY_PORT" ]; then
    echo "❌ 无法从 HTTP_PROXY='$HTTP_PROXY' 解析出主机和端口。"
    exit 1
fi

# 构造 openssl s_client 代理参数
OPENSSL_PROXY_ARGS=(-proxy "${PROXY_HOST}:${PROXY_PORT}")

if [ -n "$PROXY_USER" ]; then
    OPENSSL_PROXY_ARGS+=(-proxy_user "$PROXY_USER" -proxy_pass "pass:${PROXY_PASS}")
fi

# 打印代理信息，避免泄露密码
echo "=== 多代理 CA 自动安装 ==="

if [ -n "$PROXY_USER" ]; then
    echo "HTTP_PROXY: ${PROXY_HOST}:${PROXY_PORT}，认证用户: ${PROXY_USER}"
else
    echo "HTTP_PROXY: ${PROXY_HOST}:${PROXY_PORT}，无认证"
fi

echo "解析代理:  ${PROXY_HOST}:${PROXY_PORT}"

# ========== 2. 获取域名列表 ==========

DOMAINS=("${@}")   # 从命令行获取额外域名

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

CA_DIR="/usr/local/share/ca-certificates"
mkdir -p "$CA_DIR"

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

    if command -v update-ca-certificates &>/dev/null; then
        update-ca-certificates
    else
        echo "⚠️ 未找到 update-ca-certificates 命令，跳过系统 CA 更新。"
    fi
else
    echo "系统 CA 无新增，跳过 update-ca-certificates。"
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
