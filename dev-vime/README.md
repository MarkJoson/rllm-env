# dev-vime: Qwen3.6-35B-A3B GDN DAPO RL on Ascend NPU

Reproduces the "vime-rl" training environment for Qwen3.6-35B-A3B (GDN/MoE)
DAPO reinforcement learning on 16x Ascend 910B2C NPUs.

## Contents

```
dev-vime/
  Dockerfile       # Builds the complete dev environment
  entrypoint.sh    # Container entrypoint (sources CANN, starts sshd)
  README.md        # This file
```

## Base Image

The Dockerfile starts FROM `ascend-cann900-x86_64-huawei:base` (the dev-base
image built from `dev-base/Dockerfile`), which includes:

- Python 3.11 (bookworm) with CANN 9.0.0 toolkit at `/usr/local/Ascend/cann-9.0.0/`
- torch 2.10.0 + torch_npu 2.10.0 + triton-ascend 3.2.1
- MPICH 3.2.1, hccl_test, Docker CE CLI
- System tools: git, vim, tmux, curl, build-essential, etc.

The vime layer adds all RL-specific frameworks from source (vime, vllm,
vllm-ascend, Megatron-LM, MindSpeed, MindSpeed-MM, flash-linear-attention-npu).

## Build

```bash
# With proxy/mirror for the internal network:
docker build \
  --build-arg HTTP_PROXY=http://proxy:18080 \
  --build-arg HTTPS_PROXY=http://proxy:18080 \
  --build-arg NO_PROXY=localhost,127.0.0.1,test.huawei.com \
  --build-arg PIP_INDEX_URL=https://mirror/pypi/simple \
  --build-arg PIP_TRUSTED_HOST=mirror \
  -t dev-vime:latest \
  -f Dockerfile .

# Without proxy (build pulls from public PyPI/GitHub):
docker build -t dev-vime:latest -f Dockerfile .
```

## Run

```bash
docker run -it --rm \
  --privileged \
  --ipc=host \
  --network=host \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
  -v /usr/local/dcmi:/usr/local/dcmi \
  -v /dev:/dev \
  -v /home:/home \
  dev-vime:latest bash
```

Mounts:
- `/usr/local/Ascend/driver` -- NPU driver (required)
- `/usr/local/dcmi` -- Device management interface (required)
- `/dev` -- NPU device nodes (required)
- `/home` -- Model weights, datasets, checkpoints (recommended)

## Environment Layout (inside container)

| Path | Description |
|------|-------------|
| `/workspace/vime` | vime RL framework (branch `npu`) |
| `/workspace/vllm` | vLLM 0.21.0 (commit 7bf405d) |
| `/workspace/vllm-ascend` | vLLM Ascend plugin (branch `vime-adapter`) |
| `/workspace/exp_from_88/Megatron-LM` | Megatron-LM fork with GDN (branch `qwen36_vime_adapt`) |
| `/workspace/exp_from_88/Megatron-Bridge-slime` | Megatron-Bridge for HF conversion (branch `qwen35`) |
| `/workspace/exp_from_88/MindSpeed` | MindSpeed 0.14.1 with GDN kernels (branch `migrate-qwen36-gdn`) |
| `/workspace/MindSpeed-MM` | MindSpeed-MM SFT stack (branch `qwen36-sft`) |
| `/workspace/flash-linear-attention-npu` | FLA NPU vendor ops |
| `/root/Megatron-LM` | symlink -> `/workspace/exp_from_88/Megatron-LM` |
| `/root/Megatron-Bridge` | symlink -> `/workspace/exp_from_88/Megatron-Bridge-slime` |

## PYTHONPATH (set in run scripts)

```
export PYTHONPATH="/root/Megatron-Bridge/src:/root/Megatron-LM/:/workspace/vime:$PYTHONPATH"
```

## Model Weights (mounted from host)

- HF safetensors: `/home/s50057377/Qwen3.6-35B-A3B/`
- Megatron dist-ckpt (converted): `/home/s50057377/Qwen3.6-35B-A3B_torch_dist/`

## Training Data (mounted from host)

- DAPO math: `/home/c00937190/dapo-math-17k.jsonl`
- AIME eval: `/home/c00937190/datasets/aime-2024.jsonl`

## Running Training

```bash
cd /workspace/vime

# Optional: convert HF safetensors -> torch_dist checkpoint
bash convert_qwen36.sh

# Full DAPO RL training (16 NPUs, colocate mode)
bash scripts/run_qwen36_35b_a3b_dapo_math_npu.sh
```

## Key Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `PYTORCH_NPU_ALLOC_CONF` | `expandable_segments:True` | NPU memory allocator |
| `HCCL_BUFFSIZE` | `512` | HCCL buffer size |
| `HCCL_INTRA_ROCE_ENABLE` | `1` | RoCE network for HCCL |
| `HCCL_SOCKET_IFNAME` | `ens` | Network interface for HCCL |
| `ASCEND_RT_VISIBLE_DEVICES` | `0-15` | Visible NPU devices |
| `RAY_EXPERIMENTAL_NOSET_ASCEND_RT_VISIBLE_DEVICES` | `1` | Ray NPU integration |
| `QWEN36_CAUSAL_CONV1D_IMPL` | `triton` | Conv1D backend for GDN |

## Versions (locked -- do not change)

| Package | Version |
|---------|---------|
| Python | 3.11.15 |
| torch | 2.10.0 |
| torch_npu | 2.10.0 |
| transformers | 5.5.4 |
| vllm | 0.21.0+empty |
| vllm-ascend | 0.21.0rc1 |
| mindspeed (validated) | 0.14.1 |
| mbridge | 0.15.1 |
| ray | 2.48.0 |
| wandb | 0.27.2 |
| CANN | 9.0.0 |
| NPU driver | 26.0.rc1.b082 |
| NPU hardware | Ascend 910B2C (64GB HBM) |

## Notes

1. The container runs as root. For multi-node training, ensure SSH keys are
   configured in `~/.ssh/authorized_keys`.
2. Proxy environment variables are baked into the image but **must be cleared
   at runtime** (`unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy
   ALL_PROXY` + set `no_proxy`) to avoid silent hangs in vllm health checks.
   The run script (`run_qwen36_35b_a3b_dapo_math_npu.sh`) handles this.
3. `mindsped 0.12.1` editable artifacts from `/workspace/MindSpeed` are
   removed post-install. The validated `mindsped 0.14.1` from
   `/workspace/exp_from_88/MindSpeed` is the active one.
