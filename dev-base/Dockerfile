# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=python:3.11-bookworm
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

RUN sed -i 's/deb.debian.org/mirrors.tools.huawei.com/g' /etc/apt/sources.list \
    || sed -i "s@http://security.debian.org@https://mirrors.tools.huawei.com@g" /etc/apt/sources.list || \
    cat /etc/apt/sources.list || true

# RUN . /etc/os-release \
#     && CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}" \
#     && rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources || true \
#     && truncate -s 0 /etc/apt/sources.list 2>/dev/null || true \
#     && printf '%s\n' \
#         "deb https://mirrors.tools.huawei.com/debian/ ${CODENAME} main contrib non-free non-free-firmware" \
#         "deb https://mirrors.tools.huawei.com/debian/ ${CODENAME}-updates main contrib non-free non-free-firmware" \
#         "deb https://mirrors.tools.huawei.com/debian/ ${CODENAME}-backports main contrib non-free non-free-firmware" \
#         "deb https://mirrors.tools.huawei.com/debian/ ${CODENAME}-security main contrib non-free non-free-firmware" \
#         > /etc/apt/sources.list

RUN printf '%s\n' \
    'Acquire::http::Proxy "http://host.docker.internal:18080";' \
    'Acquire::https::Proxy "http://host.docker.internal:18080";' \
    'Acquire::http::Proxy::mirrors.tools.huawei.com "DIRECT";' \
    'Acquire::https::Proxy::mirrors.tools.huawei.com "DIRECT";' \
    'Acquire::https::Verify-Peer "false";' \
    'Acquire::https::Verify-Host "false";' \
    > /etc/apt/apt.conf

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
    locales \
    fonts-wqy-zenhei \
    fonts-wqy-microhei \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && mkdir -p /var/run/sshd

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# 4) locale
RUN locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

COPY certs /usr/local/share/ca-certificates
RUN update-ca-certificates

# 5) 安装 Docker CLI / buildx / compose plugin
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSLk https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && printf '%s\n' \
        "Types: deb" \
        "URIs: https://download.docker.com/linux/debian" \
        "Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")" \
        "Components: stable" \
        "Architectures: $(dpkg --print-architecture)" \
        "Signed-By: /etc/apt/keyrings/docker.asc" \
       > /etc/apt/sources.list.d/docker.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce-cli \
       docker-buildx-plugin \
       docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*


ENV PIP_ROOT_USER_ACTION=ignore
RUN echo '[global]' > /etc/pip.conf && \
    echo 'index-url = https://mirrors.tools.huawei.com/pypi/simple' >> /etc/pip.conf && \
    echo 'trusted-host = mirrors.tools.huawei.com' >> /etc/pip.conf && \
    echo 'timeout = 120' >> /etc/pip.conf

COPY cann /workspace/cann/
RUN python3.11 -m pip install pip setuptools==80.0.0 wheel 
RUN /workspace/cann/Ascend-cann-toolkit_9.0.0_linux-x86_64.run --install --quiet --install-for-all \
    && source /usr/local/Ascend/cann/set_env.sh \
    && /workspace/cann/Ascend-cann-910b-ops_9.0.0_linux-x86_64.run --install --quiet --install-for-all \
    && /workspace/cann/Ascend-cann-nnal_9.0.0_linux-x86_64.run --install --quiet --install-for-all


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


RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && bash -c "curl -LsSfk https://astral.sh/uv/install.sh | sh"


COPY pips /tmp/

RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && python -m pip install \
        "/tmp/torch-2.8.0+cpu-cp311-cp311-manylinux_2_28_x86_64.whl" \
        "/tmp/torch_npu-2.8.0.post4.dev20260309-cp311-cp311-manylinux_2_28_x86_64.whl" \
        "/tmp/torchvision-0.23.0+cpu-cp311-cp311-manylinux_2_28_x86_64.whl" \
        "/tmp/triton_ascend-3.4.0.dev2026012922-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl" \
        setuptools==80.0.0 \
        -i https://download.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple

# 安装 MPI
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && wget --no-check-certificate https://www.mpich.org/static/downloads/3.2.1/mpich-3.2.1.tar.gz \
    && tar -zxvf mpich-3.2.1.tar.gz \
    && cd mpich-3.2.1 \
    && ./configure --disable-fortran --prefix=/usr/local/mpich \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/mpich-3.2.1 /tmp/mpich-3.2.1.tar.gz

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