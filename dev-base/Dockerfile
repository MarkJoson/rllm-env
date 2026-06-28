# Migrated to BuildKit / buildx. Key changes vs. the classic build:
#   - cache mounts for apt + pip (torch/torch_npu are huge -> big rebuild win)
#   - bind mount for the CANN .run files (multi-GB files never enter a layer)
#   - COPY/RUN heredocs replace the brittle `bash -c $'...'` blocks
#   - PIP_NO_CACHE_DIR removed so the pip cache mount actually does something
# Build with `docker buildx build` (see notes at the bottom of this file).
 
ARG BASE_IMAGE=python:3.11-bookworm
FROM ${BASE_IMAGE}
 
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
 
ARG DEBIAN_FRONTEND=noninteractive
 
# 代理参数 (buildx forwards these automatically as build-args; ARG keeps the defaults)
ARG HTTP_PROXY=http://host.docker.internal:18080
ARG HTTPS_PROXY=http://host.docker.internal:18080
ARG NO_PROXY=host.docker.internal,localhost,127.0.0.1,::1,mirrors.tools.huawei.com,mirrors.tuna.tsinghua.edu.cn,pypi.tuna.tsinghua.edu.cn,download.pytorch.org,download-r2.pytorch.org,triton-ascend.osinfra.cn
 
ARG DEBIAN_MIRROR_HOST=mirrors.tuna.tsinghua.edu.cn
ARG APT_DIRECT_HOSTS="mirrors.tools.huawei.com"
ARG APT_INSECURE=1
 
# Docker CE apt 源
#   https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian
#   https://download.docker.com/linux/debian
ARG DOCKER_APT_BASE=https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian
 
# PyPI 源
#   https://pypi.tuna.tsinghua.edu.cn/simple
#   https://mirrors.tools.huawei.com/pypi/simple
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ARG PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
 
# Multi-arch hook: buildx sets TARGETARCH. CANN names use x86_64 / aarch64.
# Leave CANN_ARCH empty to auto-derive it from TARGETARCH in the install step.
ARG TARGETARCH
ARG CANN_ARCH=x86_64
ARG CANN_CHIP=910b
ARG CANN_VERSION=9.0.0
ARG CANN_RUNFILE=
ARG CANN_OPS_RUNFILE=
ARG CANN_NNAL_RUNFILE=
 
# Python 依赖版本
ARG SETUPTOOLS_VERSION=80.0.0
ARG TORCH_VERSION=2.10
ARG TORCH_NPU_VERSION=2.10
ARG TRITON_ASCEND_VERSION=3.2.1
 
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_ROOT_USER_ACTION=ignore \
    DOCKER_HOST=unix:///var/run/docker.sock \
    http_proxy=${HTTP_PROXY} \
    https_proxy=${HTTPS_PROXY} \
    no_proxy=${NO_PROXY} \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
 
WORKDIR /workspace

RUN cat /etc/apt/sources.list.d/debian.sources 
# --- apt mirror rewrite (edits persisted files, no mount needed) -------------
RUN set -eux; \
    if [ -f /etc/apt/sources.list ]; then \
        sed -i "s@deb.debian.org@${DEBIAN_MIRROR_HOST}@g" /etc/apt/sources.list; \
        sed -i "s@security.debian.org@${DEBIAN_MIRROR_HOST}@g" /etc/apt/sources.list; \
    fi; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i "s@deb.debian.org@${DEBIAN_MIRROR_HOST}@g" /etc/apt/sources.list.d/debian.sources; \
        sed -i "s@security.debian.org@${DEBIAN_MIRROR_HOST}@g" /etc/apt/sources.list.d/debian.sources; \
    fi; \
    true
 
# --- apt proxy + insecure config --------------------------------------------
RUN set -eux; \
    mkdir -p /etc/apt/apt.conf.d; \
    : > /etc/apt/apt.conf.d/99proxy; \
    if [ -n "${HTTP_PROXY}" ]; then \
        printf 'Acquire::http::Proxy "%s";\n' "${HTTP_PROXY}" >> /etc/apt/apt.conf.d/99proxy; \
    fi; \
    if [ -n "${HTTPS_PROXY}" ]; then \
        printf 'Acquire::https::Proxy "%s";\n' "${HTTPS_PROXY}" >> /etc/apt/apt.conf.d/99proxy; \
    fi; \
    for host in ${APT_DIRECT_HOSTS}; do \
        printf 'Acquire::http::Proxy::%s "DIRECT";\n' "${host}" >> /etc/apt/apt.conf.d/99proxy; \
        printf 'Acquire::https::Proxy::%s "DIRECT";\n' "${host}" >> /etc/apt/apt.conf.d/99proxy; \
    done; \
    if [ "${APT_INSECURE}" = "1" ]; then \
        printf '%s\n' \
            'Acquire::https::Verify-Peer "false";' \
            'Acquire::https::Verify-Host "false";' \
            >> /etc/apt/apt.conf.d/99proxy; \
    fi; \
    printf '%s\n' 'Acquire::AllowInsecureRepositories=true;' >> /etc/apt/apt.conf.d/98insecure; \
    printf '%s\n' 'Acquire::AllowDowngradeToInsecureRepositories=true;' >> /etc/apt/apt.conf.d/98insecure; \
    cat /etc/apt/apt.conf.d/99proxy

# 安装公司的勾八证书
COPY install_ca.sh /tmp/
RUN bash /tmp/install_ca.sh

# --- base packages (cache mounts; keep downloaded debs + lists in cache) -----
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    set -eux; \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        sudo \
        nano \
        vim \
        less \
        tree \
        tmux \
        jq \
        curl \
        wget \
        unzip \
        locales \
        zip \
        tar \
        patch \
        dos2unix \
        rsync \
        openssh-server \
        software-properties-common \
        procps \
        psmisc \
        lsof \
        strace \
        gdb \
        file \
        git \
        git-lfs \
        net-tools \
        iproute2 \
        iputils-ping \
        iputils-arping \
        iputils-tracepath \
        netcat-openbsd \
        iperf3 \
        htop \
        nload \
        pciutils \
        dnsutils \
        telnet \
        build-essential \
        gcc \
        g++ \
        g++-x86-64-linux-gnu \
        make \
        cmake \
        ninja-build \
        nasm \
        gawk \
        bison \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        python-is-python3 \
        libssl-dev \
        libffi-dev \
        zlib1g \
        zlib1g-dev \
        libbz2-dev \
        libsqlite3-dev \
        libxslt1-dev \
        libnuma-dev \
        libopenblas-dev \
        liblapack-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libx11-dev \
        libxext-dev \
        libxfixes-dev \
        libxi-dev \
        libepoxy-dev \
        fonts-wqy-zenhei \
        fonts-wqy-microhei \
        fonts-noto-cjk; \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
    locale-gen en_US.UTF-8; \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    mkdir -p /var/run/sshd
 
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
 
# --- Docker CE CLI / buildx / compose ----------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSLk "${DOCKER_APT_BASE}/gpg" -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    . /etc/os-release; \
    printf '%s\n' \
        "Types: deb" \
        "URIs: ${DOCKER_APT_BASE}" \
        "Suites: ${VERSION_CODENAME}" \
        "Components: stable" \
        "Architectures: $(dpkg --print-architecture)" \
        "Signed-By: /etc/apt/keyrings/docker.asc" \
        > /etc/apt/sources.list.d/docker.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin
 
# --- pip config + base build tooling (pip cache mount) -----------------------
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    set -eux; \
    printf '%s\n' \
        '[global]' \
        "index-url = ${PIP_INDEX_URL}" \
        "trusted-host = ${PIP_TRUSTED_HOST}" \
        'verify = false' \
        'timeout = 120' \
        > /etc/pip.conf; \
    cat /etc/pip.conf; \
    python3.11 -m pip install --upgrade pip "setuptools==${SETUPTOOLS_VERSION}" wheel
 
# --- CANN install via bind mount (runfiles stay out of the image layers) -----
# Build context must contain a `cann/` directory with the .run files.
RUN --mount=type=bind,source=cann,target=/tmp/cann \
    cann_arch="${CANN_ARCH}"; \
    if [ -z "${cann_arch}" ]; then \
        case "${TARGETARCH}" in \
            arm64) cann_arch=aarch64 ;; \
            amd64|"") cann_arch=x86_64 ;; \
            *) cann_arch="${TARGETARCH}" ;; \
        esac; \
    fi; \
    cann_runfile="${CANN_RUNFILE:-Ascend-cann_${CANN_VERSION}_linux-${cann_arch}.run}"; \
    ops_runfile="${CANN_OPS_RUNFILE:-Ascend-cann-${CANN_CHIP}-ops_${CANN_VERSION}_linux-${cann_arch}.run}"; \
    cann_pkg="/tmp/cann/${cann_runfile}"; \
    ops_pkg="/tmp/cann/${ops_runfile}"; \
    echo "Using CANN package: ${cann_pkg}"; \
    test -f "${cann_pkg}"; \
    bash "${cann_pkg}" --install --quiet --install-for-all; \
    if [ -f /usr/local/Ascend/cann/set_env.sh ]; then \
        source /usr/local/Ascend/cann/set_env.sh; \
    elif [ -f /usr/local/Ascend/ascend-toolkit/set_env.sh ]; then \
        source /usr/local/Ascend/ascend-toolkit/set_env.sh; \
    elif [ -f /usr/local/Ascend/ascend-toolkit/latest/set_env.sh ]; then \
        source /usr/local/Ascend/ascend-toolkit/latest/set_env.sh; \
    fi; \
    echo "Using CANN ops package: ${ops_pkg}"; \
    test -f "${ops_pkg}"; \
    bash "${ops_pkg}" --install --quiet --install-for-all; \
    if [ -n "${CANN_NNAL_RUNFILE}" ]; then \
        nnal_pkg="/tmp/cann/${CANN_NNAL_RUNFILE}"; \
        echo "Using CANN NNAL package: ${nnal_pkg}"; \
        test -f "${nnal_pkg}"; \
        bash "${nnal_pkg}" --install --quiet --install-for-all; \
    else \
        echo "CANN_NNAL_RUNFILE is empty, skip NNAL installation"; \
    fi; \
    rm -rf /tmp/Ascend*
 
# --- CANN env profile (COPY heredoc instead of bash -c $'...') ----------------
COPY <<'EOF' /etc/profile.d/ascend-cann.sh
if [ -f /usr/local/Ascend/cann/set_env.sh ]; then
  . /usr/local/Ascend/cann/set_env.sh
elif [ -f /usr/local/Ascend/ascend-toolkit/set_env.sh ]; then
  . /usr/local/Ascend/ascend-toolkit/set_env.sh
elif [ -f /usr/local/Ascend/ascend-toolkit/latest/set_env.sh ]; then
  . /usr/local/Ascend/ascend-toolkit/latest/set_env.sh
fi
 
if [ -f /usr/local/Ascend/nnal/atb/set_env.sh ]; then
  . /usr/local/Ascend/nnal/atb/set_env.sh
fi
EOF
 
# --- uv ----------------------------------------------------------------------
RUN set -eux; \
    export CURL_CA_BUNDLE=""; \
    export SSL_CERT_FILE=""; \
    echo "insecure" > ~/.curlrc; \
    echo "check_certificate = off" > ~/.wgetrc; \
    curl -LsSfk https://astral.sh/uv/install.sh | bash

RUN cat > /etc/pip.conf <<EOF
[global]
index-url = ${PIP_INDEX_URL}
extra-index-url =
    https://download.pytorch.org/whl/cpu
    https://mirrors.huaweicloud.com/ascend/repos/pypi
trusted-host =
    download.pytorch.org
    download-r2.pytorch.org
    ${PIP_TRUSTED_HOST}
    triton-ascend.osinfra.cn
EOF
 
# --- torch / torch_npu / triton-ascend (pip cache mount) ---------------------
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    set -eux; \
    pkgs="torch==${TORCH_VERSION} torch_npu==${TORCH_NPU_VERSION} setuptools==${SETUPTOOLS_VERSION}"; \
    if [ -n "${TRITON_ASCEND_VERSION}" ]; then \
        pkgs="${pkgs} triton-ascend==${TRITON_ASCEND_VERSION}"; \
    fi; \
    python -m pip install \
        ${pkgs} \
        -i https://download.pytorch.org/whl/cpu \
        --extra-index-url="${PIP_INDEX_URL}" \
 
# --- MPICH -------------------------------------------------------------------
RUN source /etc/profile.d/ascend-cann.sh || true; \
    set -eux; \
    cd /tmp; \
    wget --no-check-certificate "https://www.mpich.org/static/downloads/3.2.1/mpich-3.2.1.tar.gz"; \
    tar -zxvf "mpich-3.2.1.tar.gz"; \
    cd "mpich-3.2.1"; \
    ./configure --disable-fortran --prefix=/usr/local/mpich; \
    make -j"$(nproc)"; \
    make install; \
    rm -rf "/tmp/mpich-3.2.1" "/tmp/mpich-3.2.1.tar.gz"
 
ENV PATH=/usr/local/mpich/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/mpich/lib:${LD_LIBRARY_PATH}
 
# --- colored prompt (RUN heredoc instead of escaped one-liners) --------------
RUN <<'EOF'
set -eux
grep -q "force_color_prompt=yes" /root/.bashrc || echo 'force_color_prompt=yes' >> /root/.bashrc
cat >> /root/.bashrc <<'BASHRC'
 
# Force colored prompt and set host color to red
export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\[\033[01;31m\]${HOSTNAME:0:16}\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
BASHRC
EOF
 
ENV HCCL_IF_BASE_PORT=50000
ENV HCCL_HOST_SOCKET_PORT_RANGE=60000-60050
ENV HCCL_NPU_SOCKET_PORT_RANGE=61000-61050
ENV HCCL_SOCKET_FAMILY=AF_INET
ENV HCCL_INTRA_ROCE_ENABLE=1
ENV HCCL_INTRA_PCIE_ENABLE=0
ENV HCCL_SOCKET_IFNAME=ens
ENV HCCL_CONNECT_TIMEOUT=600
ENV HCCL_BUFFSIZE=512
ENV HCCL_WHITELIST_DISABLE=1
ENV HCCL_OP_EXPANSION_MODE=AIV
 
# --- hccl_test ---------------------------------------------------------------
RUN source /etc/profile.d/ascend-cann.sh; \
    set -eux; \
    INSTALL_DIR=/usr/local/Ascend/ascend-toolkit/latest; \
    cd "${INSTALL_DIR}/tools/hccl_test"; \
    make MPI_HOME=/usr/local/mpich ASCEND_DIR="${INSTALL_DIR}"

RUN cat /etc/profile.d/ascend-cann.sh >> /root/.bashrc

COPY .ssh /root/.ssh
COPY entrypoint.sh /workspace/entrypoint.sh
RUN chmod 700 /root/.ssh || true; \
    chmod 600 /root/.ssh/* || true; \
    chmod +x /workspace/entrypoint.sh

ENV http_proxy= https_proxy= no_proxy= HTTP_PROXY= HTTPS_PROXY= NO_PROXY=

ENTRYPOINT ["/workspace/entrypoint.sh"]
