# =============================================================================
# dev-vime: Qwen3.6-35B-A3B GDN DAPO RL training on Ascend NPU
# =============================================================================
#
# Reproduces the "vime-rl" container (node-5-52) used for:
#   - vime (npu branch) + vllm 0.21.0 + vllm-ascend 0.21.0rc1
#   - Megatron-LM (qwen36_vime_adapt) + Megatron-Bridge-slime (qwen35)
#   - MindSpeed 0.14.1 (migrate-qwen36-gdn) + MindSpeed-MM (qwen36-sft)
#   - Qwen3.6-35B-A3B GDN/MoE DAPO RL training (Route B / longctx fused path)
#
# PREREQUISITES (must be pre-installed in the base image or mounted):
#   - Ascend NPU driver (version 26.0.rc1.b082)
#   - CANN 9.0.0 toolkit at /usr/local/Ascend/cann-9.0.0/
#   - torch 2.10.0 + torch_npu 2.10.0 (pre-installed with CANN)
#   - torch_npu must be importable (import torch_npu)
#
# BUILD:
#   docker build \
#     --build-arg HTTP_PROXY=http://proxy:port \
#     --build-arg HTTPS_PROXY=http://proxy:port \
#     --build-arg NO_PROXY=localhost,127.0.0.1 \
#     --build-arg PIP_INDEX_URL=https://mirror/pypi/simple \
#     --build-arg PIP_TRUSTED_HOST=mirror \
#     -t dev-vime:latest \
#     -f Dockerfile .
#
# RUN (example):
#   docker run -it --rm \
#     --privileged \
#     --ipc=host \
#     --network=host \
#     -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
#     -v /usr/local/dcmi:/usr/local/dcmi \
#     -v /dev:/dev \
#     -v /home:/home \
#     dev-vime:latest bash
# =============================================================================

ARG BASE_IMAGE=ascend-cann900-x86_64-huawei:base
FROM ${BASE_IMAGE}

# ---------------------------------------------------------------------------
# Build-time arguments (proxy, pip mirror, repo credentials)
# ---------------------------------------------------------------------------
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy
ARG https_proxy
ARG NO_PROXY="localhost,127.0.0.1,::1"
ARG no_proxy
ARG PIP_INDEX_URL
ARG PIP_TRUSTED_HOST
ARG GIT_SSL_NO_VERIFY=1

# Persist proxy/mirror args into the image (cleared at runtime via the run script)
ENV HTTP_PROXY=${HTTP_PROXY:-} \
    HTTPS_PROXY=${HTTPS_PROXY:-} \
    http_proxy=${http_proxy:-} \
    https_proxy=${https_proxy:-} \
    NO_PROXY="${NO_PROXY}" \
    no_proxy="${no_proxy}" \
    PIP_INDEX_URL=${PIP_INDEX_URL:-} \
    PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST:-} \
    GIT_SSL_NO_VERIFY=${GIT_SSL_NO_VERIFY}

# ---------------------------------------------------------------------------
# Ascend / CANN runtime environment (mirrors /workspace/entrypoint.sh)
# ---------------------------------------------------------------------------
ENV TASK_QUEUE_ENABLE=0 \
    MULTI_STREAM_MEMORY_REUSE=2 \
    NON_MEGATRON=true \
    ASCEND_LAUNCH_BLOCKING=0 \
    ACLNN_CACHE_LIMIT=100000 \
    CPU_AFFINITY_CONF=1 \
    PYTORCH_NPU_ALLOC_CONF=expandable_segments:True

# HCCL network configuration for 910B2C
ENV HCCL_IF_BASE_PORT=50000 \
    HCCL_HOST_SOCKET_PORT_RANGE=60000-60050 \
    HCCL_NPU_SOCKET_PORT_RANGE=61000-61050 \
    HCCL_SOCKET_FAMILY=AF_INET \
    HCCL_INTRA_ROCE_ENABLE=1 \
    HCCL_INTRA_PCIE_ENABLE=0 \
    HCCL_SOCKET_IFNAME=ens \
    HCCL_CONNECT_TIMEOUT=7200 \
    HCCL_EXEC_TIMEOUT=7200 \
    HCCL_BUFFSIZE=512 \
    HCCL_WHITELIST_DISABLE=1 \
    HCCL_OP_EXPANSION_MODE=AIV

# flash-linear-attention vendor ops library path
ENV LD_LIBRARY_PATH=/usr/local/Ascend/cann-9.0.0/opp/vendors/fla_npu_transformer/op_api/lib:${LD_LIBRARY_PATH}

# ---------------------------------------------------------------------------
# System packages (dev-base already provides vim, tmux, curl, git, ssh, etc.)
# ---------------------------------------------------------------------------
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        sshpass \
        kmod \
        numactl \
        libjemalloc2 \
        ; \
    rm -rf /var/lib/apt/lists/*

# sshd for multi-node torchrun
RUN mkdir -p /var/run/sshd; \
    ssh-keygen -A >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Python dependencies (pip install --no-cache-dir)
# ---------------------------------------------------------------------------
# Upgrade pip, setuptools, wheel
RUN pip install --no-cache-dir --upgrade \
        pip \
        setuptools \
        wheel

# Core ML / training
RUN pip install --no-cache-dir \
        accelerate==1.13.0 \
        datasets==4.8.5 \
        einops==0.8.2 \
        gpytorch==1.15.2 \
        jsonargparse==4.49.0 \
        mbridge==0.15.1 \
        safetensors==0.7.0 \
        tokenizers==0.22.2 \
        transformers==5.5.4 \
        sentencepiece==0.2.1 \
        peft==0.19.1 \
        timm==1.0.27 \
        scipy==1.13.1 \
        scikit-learn==1.9.0 \
        pandas==3.0.3 \
        numpy==1.26.4 \
        ninja==1.13.0 \
        pybind11==3.0.4 \
        protobuf==6.33.6 \
        triton==3.2.0 \
        triton-ascend==3.2.1

# Distributed / RL / orchestration
RUN pip install --no-cache-dir \
        ray[default]==2.48.0 \
        vllm-router==0.1.14 \
        blobfile==3.2.0 \
        wandb==0.27.2 \
        memray==1.19.3 \
        tabulate==0.10.0 \
        ring-flash-attn==0.1.8 \
        torch_memory_saver==0.0.9.post1

# Utilities
RUN pip install --no-cache-dir \
        pylatexenc==2.10 \
        latex2sympy2==1.9.1 \
        omegaconf==2.3.1 \
        antlr4-python3-runtime==4.9.3 \
        openai==2.43.0 \
        pyarrow \
        av==17.0.1 \
        hf_xet==1.5.0 \
        modelscope==1.37.1 \
        aiohttp==3.14.0 \
        fastapi==0.123.10 \
        uvicorn==0.49.0 \
        httpx==0.28.1 \
        tiktoken==0.13.0 \
        pyzmq==27.1.0 \
        sentencepiece==0.2.1 \
        GitPython==3.1.50 \
        xgrammar==0.2.2 \
        partial-json-parser==0.2.1.1.post7 \
        llguidance==1.3.0 \
        outlines-core==0.2.14

# ---------------------------------------------------------------------------
# Workspace directory layout
# ---------------------------------------------------------------------------
WORKDIR /workspace

# ---------- 1. vime (the main RL framework) --------------------------------
RUN git clone https://github.com/MarkJoson/vime.git /workspace/vime && \
    cd /workspace/vime && \
    git checkout npu && \
    pip install --no-cache-dir -e /workspace/vime --no-build-isolation --no-deps

# ---------- 2. vllm (v0.21.0 + empty) --------------------------------------
RUN git clone https://github.com/vllm-project/vllm.git /workspace/vllm && \
    cd /workspace/vllm && \
    git checkout 7bf405de7e61c453f8111cea4a6cbb218a71a92a && \
    pip install --no-cache-dir -e /workspace/vllm --no-build-isolation --no-deps

# ---------- 3. vllm-ascend (vime-adapter branch) ---------------------------
RUN git clone https://github.com/MarkJoson/vllm-ascend.git /workspace/vllm-ascend && \
    cd /workspace/vllm-ascend && \
    git checkout vime-adapter && \
    pip install --no-cache-dir -e /workspace/vllm-ascend --no-build-isolation --no-deps

# ---------- 4. exp_from_88 repos (the validated stack) ---------------------
RUN mkdir -p /workspace/exp_from_88

# The validated Megatron-LM fork with GDN + slime-patched routing_replay
RUN git clone https://github.com/MarkJoson/Megatron-LM.git /workspace/exp_from_88/Megatron-LM && \
    cd /workspace/exp_from_88/Megatron-LM && \
    git checkout qwen36_vime_adapt

# Megatron-Bridge-slime (HF <-> megatron checkpoint conversion)
RUN git clone https://github.com/coding-famer/Megatron-Bridge-slime.git /workspace/exp_from_88/Megatron-Bridge-slime && \
    cd /workspace/exp_from_88/Megatron-Bridge-slime && \
    git checkout qwen35

# MindSpeed (GDN-capable, migrate-qwen36-gdn branch)
RUN git clone https://gitcode.com/bitszh3271/MindSpeed.git /workspace/exp_from_88/MindSpeed && \
    cd /workspace/exp_from_88/MindSpeed && \
    git checkout migrate-qwen36-gdn && \
    pip install --no-cache-dir -e /workspace/exp_from_88/MindSpeed --no-build-isolation --no-deps

# ---------- 5. MindSpeed-MM (SFT stack) ------------------------------------
RUN git clone https://github.com/MarkJoson/MindSpeed-MM.git /workspace/MindSpeed-MM && \
    cd /workspace/MindSpeed-MM && \
    git checkout qwen36-sft && \
    pip install --no-cache-dir -e /workspace/MindSpeed-MM --no-build-isolation --no-deps

# ---------- 6. flash-linear-attention-npu (vendor ops) ---------------------
RUN git clone https://github.com/flashserve/flash-linear-attention-npu.git /workspace/flash-linear-attention-npu && \
    cd /workspace/flash-linear-attention-npu && \
    git checkout eabe36b5cda0799a1672c9fc7c24cabbf12c463e && \
    pip install --no-cache-dir -e /workspace/flash-linear-attention-npu --no-build-isolation --no-deps

# ---------- 7. slime compatibility shim ------------------------------------
# Megatron-LM fork (slime v0.5.7 patch) imports "slime.utils.routing_replay".
# vime is a slime->vime rename with identical API. Create a re-export shim.
RUN mkdir -p /usr/local/lib/python3.11/site-packages/slime/utils && \
    touch /usr/local/lib/python3.11/site-packages/slime/__init__.py && \
    echo > /usr/local/lib/python3.11/site-packages/slime/utils/__init__.py && \
    cat > /usr/local/lib/python3.11/site-packages/slime/utils/routing_replay.py << 'PYEOF'
# Compatibility shim: the vendored Megatron-LM fork (slime v0.5.7 patch) imports
# "slime.utils.routing_replay". vime is a slime->vime rename with an identical
# routing_replay API, so this shim re-exports vime's implementation.
from vime.utils.routing_replay import *  # noqa: F401,F403
from vime.utils.routing_replay import (  # noqa: F401  explicit: the symbols megatron imports
    get_routing_replay_compute_topk,
    register_routing_replay,
    set_routing_replay,
    RoutingReplay,
)
PYEOF

# ---------- 8. Ensure only the validated MindSpeed 0.14.1 is active --------
RUN pip install -e /workspace/exp_from_88/MindSpeed --no-build-isolation --no-deps; \
    if [ -f /usr/local/lib/python3.11/site-packages/__editable___mindspeed_0_12_1_finder.py ]; then \
        rm -f /usr/local/lib/python3.11/site-packages/__editable___mindspeed_0_12_1_finder.py; \
        rm -f /usr/local/lib/python3.11/site-packages/__editable__.mindspeed-0.12.1.pth; \
        rm -rf /usr/local/lib/python3.11/site-packages/mindspeed-0.12.1.dist-info; \
    fi

# ---------------------------------------------------------------------------
# Symlinks (PYTHONPATH expects /root/Megatron-LM and /root/Megatron-Bridge)
# ---------------------------------------------------------------------------
RUN ln -sf /workspace/exp_from_88/Megatron-LM /root/Megatron-LM && \
    ln -sf /workspace/exp_from_88/Megatron-Bridge-slime /root/Megatron-Bridge

# ---------------------------------------------------------------------------
# Entrypoint (source CANN runtime, start sshd, exec command)
# ---------------------------------------------------------------------------
COPY entrypoint.sh /workspace/entrypoint.sh
RUN chmod +x /workspace/entrypoint.sh

# Scrub build-time proxy so it never leaks into the running container
ENV http_proxy= https_proxy= no_proxy= HTTP_PROXY= HTTPS_PROXY= NO_PROXY=

ENTRYPOINT ["/workspace/entrypoint.sh"]
CMD ["bash"]

# ---------------------------------------------------------------------------
# Default working directory
# ---------------------------------------------------------------------------
WORKDIR /workspace
