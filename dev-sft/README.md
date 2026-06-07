# qwen36sft — Qwen3.6-27B SFT image (Ascend 910B)

Fully packaged image for full-parameter SFT of **Qwen3.6-27B** on Ascend 910B via
**MindSpeed-MM (FSDP2)** + **flash-linear-attention-npu** (GDN `ascendc` kernels).

It layers an SFT framework on top of the existing **`dev-base`** image and reproduces
the validated cluster env (`ssh npu`) bit-for-bit — same git commits, same pinned pip
closure, the GDN step-time patch, the `fla_npu` AscendC vendor ops, and the runtime env
that fixes the AscendC NaN (`TASK_QUEUE_ENABLE=0`). **No venv** — installed into the
image's system `python3.11`, matching `~/qwen36-sft-env` on the cluster.

## Status — built & verified (2026-06-07)

`qwen36sft:latest` is built (16.1 GB) and **verified on a real 910B** (`docker run` with
`/dev/davinci0`): `torch 2.10.0+cpu` / `torch_npu 2.10.0` (npu_count=1), `transformers
5.10.0.dev0`, `mindspeed 0.12.1`, `mindspeed_mm 0.1`, `fla_npu 1.0.0` all import; the GDN
AscendC ops register (`torch.ops.npu.npu_recurrent_gated_delta_rule`, …); MindSpeed-MM is
at `cd345479` with the 10-file patch applied (`solve_tril.py` NT-fix present); vendor ops
at `fla_npu_transformer/op_api/lib/libcust_opapi.so`. Delivered tag uses
`FLA_BUILD_MODE=prebuilt` (bit-identical to the running cluster artifacts).

## What is pinned

| Component | Source | Commit / version |
|---|---|---|
| Base | `dev-base/Dockerfile` | CANN 9.0.0 aarch64 · torch 2.10.0+cpu · torch_npu 2.10.0 · triton-ascend 3.2.1 |
| MindSpeed-MM | github.com/Ascend/MindSpeed-MM | `cd345479` **+ patch** (`patches/mindspeed_mm_qwen36_sft.patch`) |
| MindSpeed | gitcode.com/Ascend/MindSpeed | `5753d412` |
| transformers | github.com/huggingface/transformers | `94246e68` |
| flash-linear-attention-npu | github.com/flashserve/flash-linear-attention-npu | `eabe36b` |
| pip closure | `requirements.lock.txt` | 123 pinned packages (exact `pip freeze`) |

The MindSpeed-MM patch = the GDN single-step optimisation (solve_tril `NT` recompile fix,
`prepare_chunk_indices` vectorisation, `_convert_cu_seq_lens` tolist cache) + the
profiler / step-timing instrumentation. See `GDN_STEP_OPTIMIZATION_REPORT.md`.

## Build

Prereqs (BuildKit; see `../DOCKER_RECIPES.md`):
```bash
export DOCKER_API_VERSION="$(docker version --format '{{.Server.APIVersion}}')"
```

### 1. Base (skip if `ascend-cann900-aarch64-tuna:base` already exists)
Build it via `../DOCKER_RECIPES.md` recipe #2 (tuna mirrors, CANN 9.0.0 aarch64).

### 2. SFT framework → `qwen36sft`
```bash
cd /home/sunzhihao/rllm-env
docker buildx build \
  --platform=linux/arm64 \
  -f dev-sft/Dockerfile \
  -t qwen36sft:latest \
  --build-arg BASE_IMAGE=ascend-cann900-aarch64-tuna:base \
  --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
  --build-arg PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn \
  --build-arg FLA_BUILD_MODE=source \
  --load \
  dev-sft
```

`FLA_BUILD_MODE`:
- **`source`** (default) — clones `flash-linear-attention-npu@eabe36b`, runs
  `build.sh --pkg --soc=ascend910b --vendor_name=fla_npu` (the `--vendor_name` is required:
  it both names the package and installs to `opp/vendors/fla_npu_transformer`, matching the
  runtime `LD_LIBRARY_PATH`; without it build.sh produces the built-in
  `cann-910b-ops-transformer` package under the `custom` vendor). Compiles the AscendC ops
  (fetches third_party from gitcode.com), installs the produced `.run` into CANN vendors,
  then builds + installs the `torch_custom/fla_npu` wheel. This is the "build process in
  the image" path. Heavier; needs network to gitcode.com/github.com. The AscendC compile is
  confirmed to work in-container; this path was corrected after the first build (which used
  the default vendor) but the delivered tag ships `prebuilt` for exactness.
- **`prebuilt`** — installs the validated `pkgs/fla-npu-fla_npu_linux-aarch64.run` +
  `pkgs/fla_npu-1.0.0-cp311-cp311-linux_aarch64.whl` (sha256 `9c0645f5…`, bit-identical to
  the running cluster artifacts). Fast, offline, deterministic. Use if the source build
  can't reach gitcode.com or to guarantee an exact match.

## Run

```bash
docker run -it --rm \
  --device /dev/davinci0 --device /dev/davinci1 ... \
  --device /dev/davinci_manager --device /dev/devmm_svm --device /dev/hisi_hdc \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
  -v /usr/local/dcmi:/usr/local/dcmi -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
  --shm-size=64g --network=host \
  qwen36sft:latest bash
```
Inside, the SFT entry is `python3 -m mindspeed_mm.fsdp.train.trainer <config.yaml>`
(workdir is already `/workspace/MindSpeed-MM`). The entrypoint sources the CANN env, wires
the `fla_npu_transformer` vendor lib, and starts `sshd` on 8022 for multi-node torchrun.

## Verify (on an NPU host)
```bash
python -c "import torch, torch_npu; print(torch.__version__, torch_npu.__version__)"   # 2.10.0+cpu 2.10.0
python -c "import transformers; print(transformers.__version__)"                        # Qwen3.6-capable
python -c "import mindspeed_mm, mindspeed, fla_npu; print('imports ok')"
ls /usr/local/Ascend/cann-9.0.0/opp/vendors/fla_npu_transformer                          # op_api/ op_impl/ op_proto/
echo $TASK_QUEUE_ENABLE                                                                   # 0
```
