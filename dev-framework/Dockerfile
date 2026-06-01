# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=ascend-cann900-dev:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /workspace

# 13) 安装 vllm（本地源码）
COPY pkgs/vllm /workspace/vllm
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && python -m pip install -r /workspace/vllm/requirements/build.txt \
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org \
    && cd /workspace/vllm \
    && VLLM_TARGET_DEVICE=empty python -m pip install -v -e . \
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org

ARG SOC_VERSION=Ascend910B2
ENV SOC_VERSION=${SOC_VERSION}

# 14) 安装 vllm-ascend（本地源码）
COPY pkgs/vllm-ascend /workspace/vllm-ascend
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && python -m pip install nanobind "cmake==3.28.4" \
    && python -m pip install -r /workspace/vllm-ascend/requirements.txt --no-build-isolation \
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org \
    && cd /workspace/vllm-ascend \
    && COMPILE_CUSTOM_KERNELS=1 python -m pip install -v -e . --no-build-isolation \
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org

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
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org \
    && python -m pip install -v -e /workspace/verl --no-build-isolation \
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org

# 17) 安装 rllm（本地源码）
COPY pkgs/rllm-071 /workspace/rllm-071
ENV GIT_SSL_NO_VERIFY=1
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && source /etc/profile.d/ascend-cann.sh \
    && cd /workspace/rllm-071 \
    && python -m pip install -U pip setuptools==80.0.0 wheel hatchling hatch-vcs \
    && python -m pip install -v -e . --no-build-isolation \
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org

# 18) 安装 kernelGym-NPU
COPY pkgs/kernelGym-npu-main/ /workspace/kernelGym-npu-main
RUN apt-get update \
    && apt-get install -y --no-install-recommends redis postgresql-client-common numactl libnuma-dev libjemalloc \
    && rm -rf /var/lib/apt/lists/*
RUN export http_proxy=http://host.docker.internal:18080 \
    && export https_proxy=http://host.docker.internal:18080 \
    && export no_proxy=host.docker.internal,mirrors.tools.huawei.com,localhost,127.0.0.1 \
    && cd /workspace/kernelGym-npu-main \
    && python -m pip uninstall triton triton-ascend -y \
    && python -m pip install -v triton-ascend debugpy asyncpg --no-build-isolation \
        -i https://download-r2.pytorch.org/whl/cpu --extra-index-url https://mirrors.tools.huawei.com/pypi/simple --trusted-host=download-r2.pytorch.org


# 容器使用时是使用 network=host 启动
RUN printf '%s\n' \
    'Acquire::http::Proxy "http://127.0.0.1:18080";' \
    'Acquire::https::Proxy "http://127.0.0.1:18080";' \
    'Acquire::http::Proxy::mirrors.tools.huawei.com "DIRECT";' \
    'Acquire::https::Proxy::mirrors.tools.huawei.com "DIRECT";' \
    'Acquire::https::Verify-Peer "false";' \
    'Acquire::https::Verify-Host "false";' \
    > /etc/apt/apt.conf

# 临时补丁，增加自动 source Ascend 环境变量的功能
RUN cat /etc/profile.d/ascend-cann.sh >> /root/.bashrc

COPY .ssh /root/.ssh
COPY entrypoint.sh /workspace/entrypoint.sh

ENTRYPOINT ["/workspace/entrypoint.sh"]
