#!/bin/bash
set -euo pipefail

# ========== 1. 解析 HTTP_PROXY 环境变量 ==========
if [ -z "${HTTP_PROXY:-}" ]; then
    echo "❌ 环境变量 HTTP_PROXY 未设置，无法获取代理地址。"
    echo "   请在 Dockerfile 中设置 ENV HTTP_PROXY=http://proxy_ip:port 后重试。"
    exit 1
fi

# 去除协议前缀 (http:// 或 https://)
PROXY_ADDR="${HTTP_PROXY#http://}"
PROXY_ADDR="${PROXY_ADDR#https://}"

# 分离主机和端口
PROXY_HOST="${PROXY_ADDR%:*}"
PROXY_PORT="${PROXY_ADDR##*:}"

if [ -z "$PROXY_HOST" ] || [ -z "$PROXY_PORT" ]; then
    echo "❌ 无法从 HTTP_PROXY='$HTTP_PROXY' 解析出主机和端口。"
    exit 1
fi

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
        # 系统源（构建镜像常用）
        archive.ubuntu.com
        security.ubuntu.com
        deb.debian.org
        packages.debian.org
    )
fi

echo "=== 多代理 CA 自动安装 ==="
echo "HTTP_PROXY: ${HTTP_PROXY}"
echo "解析代理:  ${PROXY_HOST}:${PROXY_PORT}"
echo "检测域名数: ${#DOMAINS[@]}"

# ========== 3. 清理临时文件 ==========
rm -f /tmp/all_certs.pem /tmp/cert-*.pem /tmp/fingerprints.txt 2>/dev/null || true
touch /tmp/fingerprints.txt

INSTALLED_COUNT=0

# ========== 4. 遍历域名提取 CA ==========
for DOMAIN in "${DOMAINS[@]}"; do
    echo -n "  [${DOMAIN}] 提取证书... "
    set +o pipefail
    timeout 8 openssl s_client \
        -proxy "${PROXY_HOST}:${PROXY_PORT}" \
        -connect "${DOMAIN}:443" \
        -showcerts </dev/null 2>/dev/null | \
        sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/all_certs.pem
    set -o pipefail

    if [ ! -s /tmp/all_certs.pem ]; then
        echo "失败（超时/不可达），跳过"
        continue
    fi

    # 分离证书
    rm -f /tmp/cert-*.pem
    awk 'BEGIN{n=0} /BEGIN CERTIFICATE/{n++; f=sprintf("/tmp/cert-%02d.pem",n-1)} {print > f}' /tmp/all_certs.pem

    FOUND_CA=0
    for cert in /tmp/cert-*.pem; do
        [ -f "$cert" ] || continue
        subject=$(openssl x509 -in "$cert" -noout -subject 2>/dev/null | sed 's/subject=//')
        issuer=$(openssl x509 -in "$cert" -noout -issuer 2>/dev/null | sed 's/issuer=//')
        if [ "$subject" = "$issuer" ] && [ -n "$subject" ]; then
            fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//' | tr -d ':')
            if grep -q "$fingerprint" /tmp/fingerprints.txt 2>/dev/null; then
                echo -n "CA 已安装，跳过 "
                FOUND_CA=1
                continue
            fi
            echo "发现新 CA: $subject"
            cp "$cert" "/usr/local/share/ca-certificates/proxy-ca-${fingerprint}.crt"
            echo "$fingerprint" >> /tmp/fingerprints.txt
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            FOUND_CA=1
        fi
    done

    if [ $FOUND_CA -eq 0 ]; then
        echo "未发现新自签名 CA"
    else
        echo "  ✓ 已安装"
    fi
done

if [ $INSTALLED_COUNT -eq 0 ]; then
    echo "❌ 未提取到任何新代理 CA 证书，请检查 HTTP_PROXY 和网络。"
    exit 1
fi

# ========== 5. 更新系统信任库 ==========
echo "更新系统 CA 库..."
update-ca-certificates --fresh

# 追加到 Python certifi（如果存在）
if command -v python3 &>/dev/null; then
    CERTIFI_PATH=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null || true)
    if [ -n "$CERTIFI_PATH" ] && [ -f "$CERTIFI_PATH" ]; then
        echo "追加 CA 到 certifi: ${CERTIFI_PATH}"
        for crt in /usr/local/share/ca-certificates/proxy-ca-*.crt; do
            cat "$crt" >> "$CERTIFI_PATH"
        done
    fi
fi

echo "=== 成功安装 ${INSTALLED_COUNT} 个代理 CA 证书 ==="