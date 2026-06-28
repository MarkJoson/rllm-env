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


# flash-linear-attention vendor ops library path
ENV LD_LIBRARY_PATH=/usr/local/Ascend/cann-9.0.0/opp/vendors/fla_npu_transformer/op_api/lib:${LD_LIBRARY_PATH}

RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        sshpass \
        kmod \
        numactl \
        libjemalloc2 \
    && rm -rf /var/lib/apt/lists/*


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
        triton-ascend==3.2.1 \

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

RUN git clone https://github.com/MarkJoson/vime.git /workspace/vime && \
    cd /workspace/vime && \
    git checkout npu && \
    pip install --no-cache-dir -e /workspace/vime --no-build-isolation --no-deps


RUN git clone https://github.com/vllm-project/vllm.git /workspace/vllm && \
    cd /workspace/vllm && \
    git checkout 7bf405de7e61c453f8111cea4a6cbb218a71a92a && \
    pip install --no-cache-dir -e /workspace/vllm --no-build-isolation --no-deps

    
RUN git clone https://github.com/MarkJoson/vllm-ascend.git /workspace/vllm-ascend && \
    cd /workspace/vllm-ascend && \
    git checkout vime-adapter && \
    pip install --no-cache-dir -e /workspace/vllm-ascend --no-build-isolation --no-deps


RUN mkdir -p /workspace

# The validated Megatron-LM fork with GDN + slime-patched routing_replay
RUN git clone https://github.com/MarkJoson/Megatron-LM.git /workspace/Megatron-LM && \
    cd /workspace/Megatron-LM && \
    git checkout qwen36_vime_adapt

# Megatron-Bridge-slime (HF <-> megatron checkpoint conversion)
RUN git clone https://github.com/coding-famer/Megatron-Bridge-slime.git /workspace/Megatron-Bridge-slime && \
    cd /workspace/Megatron-Bridge-slime && \
    git checkout qwen35

# MindSpeed (GDN-capable, migrate-qwen36-gdn branch)
RUN git clone https://gitcode.com/bitszh3271/MindSpeed.git /workspace/MindSpeed && \
    cd /workspace/MindSpeed && \
    git checkout migrate-qwen36-gdn && \
    pip install --no-cache-dir -e /workspace/MindSpeed --no-build-isolation --no-deps

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
# RUN mkdir -p /usr/local/lib/python3.11/site-packages/slime/utils && \
#     touch /usr/local/lib/python3.11/site-packages/slime/__init__.py && \
#     touch /usr/local/lib/python3.11/site-packages/slime/utils/__init__.py && \
#     printf '%s\n' \
#       '# Compatibility shim: re-export vime routing_replay under the slime import.' \
#       'from vime.utils.routing_replay import *  # noqa: F401,F403' \
#       'from vime.utils.routing_replay import (  # noqa: F401' \
#       '    get_routing_replay_compute_topk,' \
#       '    register_routing_replay,' \
#       '    set_routing_replay,' \
#       '    RoutingReplay,' \
#       ')' \
#       > /usr/local/lib/python3.11/site-packages/slime/utils/routing_replay.py

# Scrub build-time proxy so it never leaks into the running container
ENV http_proxy= https_proxy= no_proxy= HTTP_PROXY= HTTPS_PROXY= NO_PROXY=

ENTRYPOINT ["/workspace/entrypoint.sh"]
CMD ["bash"]

WORKDIR /workspace
