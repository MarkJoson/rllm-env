#!/bin/bash
# qwen36sft entrypoint: source the Ascend/CANN runtime, wire the fla_npu vendor
# op library, start sshd (for multi-node torchrun), then exec the command.
set -e

# --- Ascend / CANN runtime ---------------------------------------------------
if [ -f /usr/local/Ascend/ascend-toolkit/set_env.sh ]; then
  source /usr/local/Ascend/ascend-toolkit/set_env.sh
elif [ -f /usr/local/Ascend/cann/set_env.sh ]; then
  source /usr/local/Ascend/cann/set_env.sh
fi
[ -f /usr/local/Ascend/nnal/atb/set_env.sh ] && source /usr/local/Ascend/nnal/atb/set_env.sh || true

# --- flash-linear-attention-npu AscendC vendor ops ---------------------------
export LD_LIBRARY_PATH=/usr/local/Ascend/cann-9.0.0/opp/vendors/fla_npu_transformer/op_api/lib:${LD_LIBRARY_PATH}

# --- validated SFT runtime env (also baked as Docker ENV; re-assert here) ----
export TASK_QUEUE_ENABLE=${TASK_QUEUE_ENABLE:-0}
export MULTI_STREAM_MEMORY_REUSE=${MULTI_STREAM_MEMORY_REUSE:-2}
export NON_MEGATRON=${NON_MEGATRON:-true}
export ACLNN_CACHE_LIMIT=${ACLNN_CACHE_LIMIT:-100000}
export CPU_AFFINITY_CONF=${CPU_AFFINITY_CONF:-1}
export PYTORCH_NPU_ALLOC_CONF=${PYTORCH_NPU_ALLOC_CONF:-expandable_segments:True}

# --- sshd for multi-node launches (best-effort) ------------------------------
if command -v sshd >/dev/null 2>&1; then
  mkdir -p /var/run/sshd
  ssh-keygen -A >/dev/null 2>&1 || true
  /usr/sbin/sshd -p 8022 2>/dev/null || true
fi

if [ "$#" -eq 0 ]; then
  exec bash
else
  exec "$@"
fi
