ARG BASE_IMAGE=ubuntu:22.04
#swr.cn-south-1.myhuaweicloud.com/ascendhub/cann:9.0.0-beta.2-910b-ubuntu22.04-py3.11
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DOCKER_HOST=unix:///var/run/docker.sock

WORKDIR /workspace

COPY cann /workspace/cann/

RUN /workspace/cann/Ascend-cann-toolkit_9.0.0_linux-x86_64.run --install --quiet --install-for-all \
    && /workspace/cann/Ascend-cann-nnal_9.0.0_linux-x86_64.run --install --quiet --install-for-all \
    && /workspace/cann/Ascend-cann-910b-ops_9.0.0_linux-x86_64.run --install --quiet --install-for-all

# 0) 基础镜像校验：应为 Ascend CANN 基础镜像
RUN if [[ ! -f /usr/local/Ascend/cann/set_env.sh && \
          ! -f /usr/local/Ascend/ascend-toolkit/set_env.sh && \
          ! -f /usr/local/Ascend/ascend-toolkit/latest/set_env.sh ]]; then \
      echo >&2 "ERROR: BASE_IMAGE does not look like an Ascend CANN image."; \
      echo >&2 "Expected Ascend CANN env script under /usr/local/Ascend"; \
      exit 1; \
    fi

# 1) 切换 Ubuntu 软件源到华为镜像
RUN . /etc/os-release \
    && CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}" \
    && (cp -f /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true) \
    && printf '%s\n' \
        "deb https://mirrors.tools.huawei.com/ubuntu/ ${CODENAME} main restricted universe multiverse" \
        "deb https://mirrors.tools.huawei.com/ubuntu/ ${CODENAME}-updates main restricted universe multiverse" \
        "deb https://mirrors.tools.huawei.com/ubuntu/ ${CODENAME}-backports main restricted universe multiverse" \
        "deb https://mirrors.tools.huawei.com/ubuntu/ ${CODENAME}-security main restricted universe multiverse" \
        > /etc/apt/sources.list

COPY apt.conf /etc/apt/
COPY certs /usr/local/share/ca-certificates
RUN update-ca-certificates

# 清理可能冲突的额外源
RUN rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources || true

# 3) 安装系统依赖、开发工具、监控工具、网络排障工具、中文环境
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
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
    libclang-15-dev \
    locales \
    language-pack-zh-hans \
    fonts-wqy-zenhei \
    fonts-wqy-microhei \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

# 4) locale
RUN locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# 5) 安装 Docker CLI / buildx / compose plugin，用于 Docker-out-of-Docker
RUN install -m 0755 -d /etc/apt/keyrings \
    && export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && curl -fsSLk https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && printf "Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n" \
       "${UBUNTU_CODENAME:-$VERSION_CODENAME}" "$(dpkg --print-architecture)" \
       > /etc/apt/sources.list.d/docker.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce-cli \
       docker-buildx-plugin \
       docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

    RUN mkdir -p /var/run/sshd

RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && bash -c "curl -LsSfk https://astral.sh/uv/install.sh | sh"

RUN echo 'if [ -f /usr/local/Ascend/cann/set_env.sh ]; then' > /etc/profile.d/ascend-cann.sh && \
    echo '  source /usr/local/Ascend/cann/set_env.sh' >> /etc/profile.d/ascend-cann.sh && \
    echo 'elif [ -f /usr/local/Ascend/ascend-toolkit/set_env.sh ]; then' >> /etc/profile.d/ascend-cann.sh && \
    echo '  source /usr/local/Ascend/ascend-toolkit/set_env.sh' >> /etc/profile.d/ascend-cann.sh && \
    echo 'elif [ -f /usr/local/Ascend/ascend-toolkit/latest/set_env.sh ]; then' >> /etc/profile.d/ascend-cann.sh && \
    echo '  source /usr/local/Ascend/ascend-toolkit/latest/set_env.sh' >> /etc/profile.d/ascend-cann.sh && \
    echo 'fi' >> /etc/profile.d/ascend-cann.sh && \
    echo '' >> /etc/profile.d/ascend-cann.sh && \
    echo 'if [ -f /usr/local/Ascend/nnal/atb/set_env.sh ]; then' >> /etc/profile.d/ascend-cann.sh && \
    echo '  source /usr/local/Ascend/nnal/atb/set_env.sh' >> /etc/profile.d/ascend-cann.sh && \
    echo 'fi' >> /etc/profile.d/ascend-cann.sh


RUN echo '[global]' > /etc/pip.conf && \
    echo 'index-url = https://mirrors.tools.huawei.com/pypi/simple' >> /etc/pip.conf && \
    echo 'trusted-host = mirrors.tools.huawei.com' >> /etc/pip.conf && \
    echo 'timeout = 120' >> /etc/pip.conf

ENV PIP_ROOT_USER_ACTION=ignore

COPY torch-2.8.0+cpu-cp311-cp311-manylinux_2_28_x86_64.whl /tmp/torch-2.8.0+cpu-cp311-cp311-manylinux_2_28_x86_64.whl

RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && python -m pip install \
        "/tmp/torch-2.8.0+cpu-cp311-cp311-manylinux_2_28_x86_64.whl" \
        torch_npu==2.8.0 \
        torchvision \
        triton-ascend \
        setuptools==80.0.0 \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple

# ===========================

# 安装mpi
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && wget --no-check-certificate https://www.mpich.org/static/downloads/3.2.1/mpich-3.2.1.tar.gz && \
    tar -zxvf mpich-3.2.1.tar.gz && \
    cd mpich-3.2.1 && \
    ./configure --disable-fortran  --prefix=/usr/local/mpich && \
    make -j"$(nproc)" && \
    make install && \
    rm -rf /tmp/mpich-3.2.1 /tmp/mpich-3.2.1.tar.gz

ENV PATH=/usr/local/mpich/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/mpich/lib:${LD_LIBRARY_PATH}

RUN grep -q "force_color_prompt=yes" /root/.bashrc || echo 'force_color_prompt=yes' >> /root/.bashrc && \
    echo '' >> /root/.bashrc && \
    echo '# Force colored prompt and set host color to red' >> /root/.bashrc && \
    echo 'export PS1='\''${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\[\033[01;31m\]\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '\''' >> /root/.bashrc

# 配置 HCCL 以及相关工具
ENV HCCL_SOCKET_FAMILY=AF_INET
ENV HCCL_SOCKET_IFNAME=eth,enp,ens,end
ENV HCCL_CONNECT_TIMEOUT=600
ENV HCCL_BUFFSIZE=2048

RUN export INSTALL_DIR=/usr/local/Ascend/ascend-toolkit/latest \
    && source /etc/profile.d/ascend-cann.sh \
    && cd ${INSTALL_DIR}/tools/hccl_test \
    && make MPI_HOME=/usr/local/mpich ASCEND_DIR=${INSTALL_DIR}

# ===========================

# 13) 安装 vllm（本地源码）
COPY pkgs/vllm /workspace/vllm
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && python -m pip install -r /workspace/vllm/requirements/build.txt \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple \
    && cd /workspace/vllm \
    && VLLM_TARGET_DEVICE=empty python -m pip install -v -e . \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple

ARG SOC_VERSION=Ascend910B2
ENV SOC_VERSION=${SOC_VERSION}

# 14) 安装 vllm-ascend（本地源码）
COPY pkgs/vllm-ascend /workspace/vllm-ascend
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && test -f /usr/local/Ascend/nnal/atb/set_env.sh \
    && python -m pip install nanobind "cmake==3.28.4" \
    && python -m pip install -r /workspace/vllm-ascend/requirements.txt --no-build-isolation \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple \
    && cd /workspace/vllm-ascend \
    && COMPILE_CUSTOM_KERNELS=1 python -m pip install -v -e . --no-build-isolation \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple

# 15) 安装 Megatron-LM 与 MindSpeed（本地源码）
COPY pkgs/Megatron-LM /workspace/Megatron-LM
COPY pkgs/MindSpeed /workspace/MindSpeed
RUN source /etc/profile.d/ascend-cann.sh \
    && python -m pip install -e /workspace/Megatron-LM \
    && python -m pip install -e /workspace/MindSpeed \
    && python -m pip install mbridge

# 16) 安装 verl（本地源码）
COPY pkgs/verl /workspace/verl
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && python -m pip install -r /workspace/verl/requirements-npu.txt --no-build-isolation \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple \
    && python -m pip install -v -e /workspace/verl --no-build-isolation \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple


# 16) rllm
COPY pkgs/rllm-071 /workspace/rllm-071
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && cd /workspace/rllm-071 && python -m pip install -U pip setuptools==80.0.0 wheel hatchling hatch-vcs && \
    python -m pip install -v -e . --no-build-isolation \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple

# 其他
COPY .ssh /root/.ssh
COPY entrypoint.sh /workspace/entrypoint.sh

ENTRYPOINT ["/workspace/entrypoint.sh"]
