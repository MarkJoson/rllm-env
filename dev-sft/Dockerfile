# =============================================================================
# qwen36sft — Qwen3.6-27B full-parameter SFT on Ascend 910B
#   MindSpeed-MM (FSDP2) + flash-linear-attention-npu (GDN ascendc kernels)
#
# Layered on the existing dev-base image
#   (CANN 9.0.0 aarch64 + torch 2.10.0+cpu + torch_npu 2.10.0 +
#    triton-ascend 3.2.1 + MPICH + hccl_test).
#
# Reproduces the *validated* cluster env (ssh npu) bit-for-bit:
#   - same git commits (pinned below), same pinned pip closure (requirements.lock.txt)
#   - the GDN step-time patch applied to MindSpeed-MM
#   - the fla_npu AscendC vendor ops + torch_custom wheel
#   - the runtime env that fixes the AscendC NaN (TASK_QUEUE_ENABLE=0) and wires
#     the vendor op_api lib onto LD_LIBRARY_PATH
#
# No venv: everything is installed into the image's system python (python3.11),
# matching `~/qwen36-sft-env` on the cluster exactly.
#
# BuildKit required (cache mounts + heredocs); build with `docker buildx build`.
# =============================================================================

ARG BASE_IMAGE=ascend-cann900-aarch64-tuna:base
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /workspace

# ---- network / mirror knobs (mirror dev-base; default = no proxy + tuna) ----
ARG HTTP_PROXY=
ARG HTTPS_PROXY=
ARG NO_PROXY=
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ARG PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
ENV http_proxy=${HTTP_PROXY} \
    https_proxy=${HTTPS_PROXY} \
    no_proxy=${NO_PROXY} \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_INDEX_URL=${PIP_INDEX_URL} \
    PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST} \
    GIT_SSL_NO_VERIFY=1 \
    PYTHONDONTWRITEBYTECODE=1

# ---- pinned sources: git remote + commit id (exactly what runs on the cluster) ----
ARG MINDSPEED_REPO=https://gitcode.com/Ascend/MindSpeed.git
ARG MINDSPEED_COMMIT=5753d412882317b113e08103a2b0b7155345096a
ARG MINDSPEED_MM_REPO=https://github.com/Ascend/MindSpeed-MM.git
ARG MINDSPEED_MM_COMMIT=cd34547968d9de915b826f1cba9e05d27153167b
ARG TRANSFORMERS_COMMIT=94246e689c03551bd97624d436de4c7e2d937063
ARG FLA_REPO=https://github.com/flashserve/flash-linear-attention-npu.git
ARG FLA_COMMIT=eabe36b5cda0799a1672c9fc7c24cabbf12c463e
ARG FLA_SOC=ascend910b
# vendor name -> installs the AscendC ops to opp/vendors/${FLA_VENDOR_NAME}_transformer
# (must be "fla_npu" to match the runtime LD_LIBRARY_PATH = .../fla_npu_transformer/op_api/lib)
ARG FLA_VENDOR_NAME=fla_npu
# fla build mode: "source" = clone @commit and build the AscendC ops + wheel
#                 "prebuilt" = install the validated .run + .whl staged in pkgs/
ARG FLA_BUILD_MODE=source

ARG CANN_HOME=/usr/local/Ascend/cann-9.0.0
ARG FLA_VENDOR_LIB=/usr/local/Ascend/cann-9.0.0/opp/vendors/fla_npu_transformer/op_api/lib

# -----------------------------------------------------------------------------
# 1) pinned python dependency closure — the exact resolved env from the cluster.
#    torch / torch_npu / triton-ascend already live in the base; the cpu +
#    triton-ascend extra indexes let the +cpu / triton pins resolve cleanly.
# -----------------------------------------------------------------------------
COPY requirements.lock.txt /workspace/requirements.lock.txt
RUN set -ex; source /etc/profile.d/ascend-cann.sh || true; \
    python -m pip install --no-deps -r /workspace/requirements.lock.txt \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        --extra-index-url https://triton-ascend.osinfra.cn/pypi/simple \
        --trusted-host download.pytorch.org \
        --trusted-host download-r2.pytorch.org \
        --trusted-host "${PIP_TRUSTED_HOST}" \
        --trusted-host triton-ascend.osinfra.cn

# -----------------------------------------------------------------------------
# 2) transformers @ pinned HF commit (Qwen3.6 support). Deps already locked.
# -----------------------------------------------------------------------------
RUN set -ex; \
    python -m pip install --no-deps --no-build-isolation \
        "transformers @ git+https://github.com/huggingface/transformers.git@${TRANSFORMERS_COMMIT}"

# -----------------------------------------------------------------------------
# 3) MindSpeed (gitcode @commit) — editable, deps already locked.
# -----------------------------------------------------------------------------
RUN set -ex; source /etc/profile.d/ascend-cann.sh || true; \
    git clone "${MINDSPEED_REPO}" /workspace/MindSpeed; \
    git -C /workspace/MindSpeed checkout --detach "${MINDSPEED_COMMIT}"; \
    python -m pip install -e /workspace/MindSpeed --no-deps

# -----------------------------------------------------------------------------
# 4) MindSpeed-MM (github @commit) + GDN step-time patch — editable.
#    This is the repo trainer.py is launched from.
# -----------------------------------------------------------------------------
COPY patches/mindspeed_mm_qwen36_sft.patch /workspace/mindspeed_mm_qwen36_sft.patch
RUN set -ex; source /etc/profile.d/ascend-cann.sh || true; \
    git clone "${MINDSPEED_MM_REPO}" /workspace/MindSpeed-MM; \
    git -C /workspace/MindSpeed-MM checkout --detach "${MINDSPEED_MM_COMMIT}"; \
    git -C /workspace/MindSpeed-MM apply --check /workspace/mindspeed_mm_qwen36_sft.patch; \
    git -C /workspace/MindSpeed-MM apply --whitespace=nowarn /workspace/mindspeed_mm_qwen36_sft.patch; \
    python -m pip install -e /workspace/MindSpeed-MM --no-deps

# -----------------------------------------------------------------------------
# 5) flash-linear-attention-npu : AscendC GDN vendor ops + torch_custom wheel.
#    source  : clone @commit -> build.sh --pkg --soc -> install .run -> build whl
#    prebuilt: install the validated .run + .whl from pkgs/ (bit-identical)
# -----------------------------------------------------------------------------
COPY pkgs/ /workspace/fla-prebuilt/
RUN set -ex; source /etc/profile.d/ascend-cann.sh; \
    if [ "${FLA_BUILD_MODE}" = "prebuilt" ]; then \
        echo ">>> FLA prebuilt mode: installing validated .run + .whl"; \
        bash /workspace/fla-prebuilt/fla-npu-fla_npu_linux-aarch64.run --quiet --install-for-all; \
        python -m pip install --no-deps --force-reinstall \
            /workspace/fla-prebuilt/fla_npu-1.0.0-cp311-cp311-linux_aarch64.whl; \
    else \
        echo ">>> FLA source mode: clone @${FLA_COMMIT} and build"; \
        git clone "${FLA_REPO}" /workspace/flash-linear-attention-npu; \
        git -C /workspace/flash-linear-attention-npu checkout --detach "${FLA_COMMIT}"; \
        cd /workspace/flash-linear-attention-npu; \
        bash build.sh --pkg --soc="${FLA_SOC}" --vendor_name="${FLA_VENDOR_NAME}"; \
        run_pkg="$(ls build_out/*.run)"; \
        bash "${run_pkg}" --quiet --install-for-all; \
        cd torch_custom/fla_npu; bash build.sh; \
    fi; \
    test -d "${CANN_HOME}/opp/vendors/fla_npu_transformer"; \
    python -m pip show fla_npu >/dev/null

# -----------------------------------------------------------------------------
# 6) runtime env — the validated config.
#    TASK_QUEUE_ENABLE=0 is the AscendC-GDN NaN fix (async task-queue race);
#    the vendor op_api/lib must be on LD_LIBRARY_PATH for the custom ops to load.
# -----------------------------------------------------------------------------
ENV TASK_QUEUE_ENABLE=0 \
    MULTI_STREAM_MEMORY_REUSE=2 \
    NON_MEGATRON=true \
    ASCEND_LAUNCH_BLOCKING=0 \
    ACLNN_CACHE_LIMIT=100000 \
    CPU_AFFINITY_CONF=1 \
    PYTORCH_NPU_ALLOC_CONF=expandable_segments:True \
    HCCL_CONNECT_TIMEOUT=7200 \
    HCCL_EXEC_TIMEOUT=7200
ENV LD_LIBRARY_PATH=${FLA_VENDOR_LIB}:${LD_LIBRARY_PATH}

# scrub build-time proxy so it never leaks into the running container
ENV http_proxy= https_proxy= no_proxy= HTTP_PROXY= HTTPS_PROXY= NO_PROXY=

COPY entrypoint.sh /workspace/entrypoint.sh
RUN dos2unix /workspace/entrypoint.sh 2>/dev/null || true; chmod +x /workspace/entrypoint.sh
WORKDIR /workspace/MindSpeed-MM
ENTRYPOINT ["/workspace/entrypoint.sh"]
CMD ["bash"]
