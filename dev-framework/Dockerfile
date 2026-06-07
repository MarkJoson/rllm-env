ARG BASE_IMAGE=ascend-cann900-dev:base
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /workspace
# 功能开关
ARG INSTALL_VLLM=1
ARG INSTALL_VLLM_ASCEND=1
ARG INSTALL_MEGATRON_MINDSPEED=1
ARG INSTALL_VERL=1
ARG INSTALL_RLLM=1
ARG INSTALL_KERNELGYM=1
# Python 基础包版本
ARG SETUPTOOLS_VERSION=80.0.0
# 系统基础依赖
RUN apt-get update; \
    apt-get install -y --no-install-recommends \
        redis \
        postgresql-client-common \
        openssh-server \
        numactl \
        libnuma-dev \
        libjemalloc2; \
    rm -rf /var/lib/apt/lists/*
# 基础 Python 依赖
RUN source /etc/profile.d/ascend-cann.sh || true; \
    python -m pip install -U \
        pip \
        "setuptools==${SETUPTOOLS_VERSION}" \
        wheel \
        hatchling \
        hatch-vcs \
        nanobind \
        "cmake==3.28.4" \
        nputop \
        debugpy \
        asyncpg; \
    python -m pip uninstall triton triton-ascend -y || true; \
    python -m pip install -v \
        debugpy \
        asyncpg \
        mbridge \
        --no-build-isolation
# 安装 vllm，本地源码
COPY pkgs/vllm /workspace/vllm
RUN if [ "${INSTALL_VLLM}" = "1" ]; then \
        source /etc/profile.d/ascend-cann.sh; \
        python -m pip install -r /workspace/vllm/requirements/build.txt; \
        cd /workspace/vllm; \
        VLLM_TARGET_DEVICE=empty \
            python -m pip install -v -e .; \
    fi
# 安装 vllm-ascend，本地源码
COPY pkgs/vllm-ascend /workspace/vllm-ascend
RUN if [ "${INSTALL_VLLM_ASCEND}" = "1" ]; then \
        source /etc/profile.d/ascend-cann.sh; \
        python -m pip install \
            nanobind \
            "cmake==3.28.4"; \
        python -m pip install -r /workspace/vllm-ascend/requirements.txt \
            --no-build-isolation; \
        cd /workspace/vllm-ascend; \
        COMPILE_CUSTOM_KERNELS=1 \
            python -m pip install -v -e . \
            --no-build-isolation; \
    fi
# 安装 Megatron-LM 与 MindSpeed，本地源码
COPY pkgs/Megatron-LM /workspace/Megatron-LM
COPY pkgs/MindSpeed /workspace/MindSpeed
RUN if [ "${INSTALL_MEGATRON_MINDSPEED}" = "1" ]; then \
        source /etc/profile.d/ascend-cann.sh; \
        python -m pip install -e /workspace/Megatron-LM; \
        python -m pip install -e /workspace/MindSpeed; \
        python -m pip install mbridge; \
    fi
# 安装 verl，本地源码
COPY pkgs/verl /workspace/verl
RUN if [ "${INSTALL_VERL}" = "1" ]; then \
        source /etc/profile.d/ascend-cann.sh; \
        python -m pip install -r /workspace/verl/requirements-npu.txt \
            --no-build-isolation; \
        python -m pip install -v -e /workspace/verl \
            --no-build-isolation; \
    fi
# 安装 rllm，本地源码
COPY pkgs/rllm-071 /workspace/rllm-071
RUN if [ "${INSTALL_RLLM}" = "1" ]; then \
        source /etc/profile.d/ascend-cann.sh; \
        cd /workspace/rllm-071; \
        python -m pip install -U \
            pip \
            "setuptools==${SETUPTOOLS_VERSION}" \
            wheel \
            hatchling \
            hatch-vcs; \
        python -m pip install -v -e . \
            --no-build-isolation; \
    fi
# 安装 kernelGym-NPU
COPY pkgs/kernelGym-npu-main/ /workspace/kernelGym-npu-main
RUN if [ "${INSTALL_KERNELGYM}" = "1" ]; then \
        source /etc/profile.d/ascend-cann.sh || true; \
        cd /workspace/kernelGym-npu-main; \
        python -m pip uninstall triton triton-ascend -y || true; \
        python -m pip install -v \
            triton-ascend \
            --no-build-isolation; \
    fi
# 自动 source Ascend 环境变量
# 固定默认行为：始终追加
RUN cat /etc/profile.d/ascend-cann.sh >> /root/.bashrc
# SSH 与入口脚本
COPY .ssh /root/.ssh
COPY entrypoint.sh /workspace/entrypoint.sh
RUN chmod 700 /root/.ssh || true; \
    chmod 600 /root/.ssh/* || true; \
    chmod +x /workspace/entrypoint.sh
ENTRYPOINT ["/workspace/entrypoint.sh"]
