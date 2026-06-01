# Docker Build Recipes

本仓库的参数化构建分两层：

- `dev-base/Dockerfile`：系统工具、Docker CLI、CANN、PyTorch/torch_npu、triton-ascend、MPI、hccl_test。
- `dev-framework/Dockerfile`：基于 base 镜像安装本地源码包，默认安装全部包。

所有命令都默认在仓库根目录执行。

## 前置检查

`dev-base/Dockerfile` 会从 `dev-base/cann/` 读取 CANN 安装包。可以直接传完整文件名，也可以不传文件名、让 Dockerfile 根据版本和架构生成默认名：

```text
CANN_RUNFILE      默认 Ascend-cann_${CANN_VERSION}_linux-${CANN_ARCH}.run
CANN_OPS_RUNFILE  默认 Ascend-cann-${CANN_CHIP}-ops_${CANN_VERSION}_linux-${CANN_ARCH}.run
CANN_NNAL_RUNFILE 默认空，留空则跳过 NNAL
```

因此构建前先确认安装包存在：

```bash
find dev-base/cann -maxdepth 1 -type f | sort
```

如果构建 `8.5.2` 且本地包名仍是旧的 `Ascend-cann-toolkit_8.5.2_linux-aarch64.run`，直接传 `--build-arg CANN_RUNFILE=Ascend-cann-toolkit_8.5.2_linux-aarch64.run` 即可，不需要复制或改名。

如果要构建 `x86_64`，请把对应架构的 CANN 包放入 `dev-base/cann/`，例如：

```text
Ascend-cann_9.0.0_linux-x86_64.run
Ascend-cann-910b-ops_9.0.0_linux-x86_64.run
Ascend-cann-nnal_9.0.0_linux-x86_64.run
```

## 1. x86_64 + Huawei 代理 + CANN 9.0.0 + 全部包

这个 recipe 构建完整环境：先构建 `base`，再构建带全部本地源码包的 `framework`。

```bash
DOCKER_BUILDKIT=1 docker build \
  --platform=linux/amd64 \
  --add-host=host.docker.internal:host-gateway \
  -f dev-base/Dockerfile \
  -t ascend-cann900-x86_64-huawei:base \
  --build-arg BASE_IMAGE=python:3.11-bookworm \
  --build-arg HTTP_PROXY=http://host.docker.internal:18080 \
  --build-arg HTTPS_PROXY=http://host.docker.internal:18080 \
  --build-arg NO_PROXY=host.docker.internal,localhost,127.0.0.1,::1,mirrors.tools.huawei.com,download.pytorch.org,download-r2.pytorch.org,triton-ascend.osinfra.cn \
  --build-arg DEBIAN_MIRROR_HOST=mirrors.tools.huawei.com \
  --build-arg APT_DIRECT_HOSTS=mirrors.tools.huawei.com \
  --build-arg APT_INSECURE=1 \
  --build-arg DOCKER_APT_BASE=https://mirrors.tools.huawei.com/docker-ce/linux/debian \
  --build-arg PIP_INDEX_URL=https://mirrors.tools.huawei.com/pypi/simple \
  --build-arg PIP_TRUSTED_HOST=mirrors.tools.huawei.com \
  --build-arg CANN_ARCH=x86_64 \
  --build-arg CANN_CHIP=910b \
  --build-arg CANN_VERSION=9.0.0 \
  --build-arg CANN_RUNFILE=Ascend-cann_9.0.0_linux-x86_64.run \
  --build-arg CANN_OPS_RUNFILE=Ascend-cann-910b-ops_9.0.0_linux-x86_64.run \
  --build-arg CANN_NNAL_RUNFILE=Ascend-cann-nnal_9.0.0_linux-x86_64.run \
  --build-arg TORCH_VERSION=2.10 \
  --build-arg TORCH_NPU_VERSION=2.10 \
  --build-arg TRITON_ASCEND_VERSION=3.2.1 \
  dev-base
```

```bash
DOCKER_BUILDKIT=1 docker build \
  --platform=linux/amd64 \
  --add-host=host.docker.internal:host-gateway \
  -f dev-framework/Dockerfile \
  -t ascend-cann900-x86_64-huawei:framework \
  --build-arg BASE_IMAGE=ascend-cann900-x86_64-huawei:base \
  --build-arg INSTALL_VLLM=1 \
  --build-arg INSTALL_VLLM_ASCEND=1 \
  --build-arg INSTALL_MEGATRON_MINDSPEED=1 \
  --build-arg INSTALL_VERL=1 \
  --build-arg INSTALL_RLLM=1 \
  --build-arg INSTALL_KERNELGYM=1 \
  dev-framework
```

## 2. 无代理 + 清华源 + CANN 9.0.0

这个 recipe 显式清空代理，并使用清华 Debian/Docker/PyPI 源。下面以当前仓库已有的 `aarch64` CANN 包为例；如果要构建 `x86_64`，把 `--platform` 和 `CANN_ARCH` 改成 `linux/amd64`、`x86_64`，并放入对应安装包。

```bash
DOCKER_BUILDKIT=1 docker build \
  --platform=linux/arm64 \
  -f dev-base/Dockerfile \
  -t ascend-cann900-aarch64-tuna:base \
  --build-arg BASE_IMAGE=python:3.11-bookworm \
  --build-arg HTTP_PROXY= \
  --build-arg HTTPS_PROXY= \
  --build-arg NO_PROXY= \
  --build-arg DEBIAN_MIRROR_HOST=mirrors.tuna.tsinghua.edu.cn \
  --build-arg APT_DIRECT_HOSTS= \
  --build-arg APT_INSECURE=0 \
  --build-arg DOCKER_APT_BASE=https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian \
  --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
  --build-arg PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn \
  --build-arg CANN_ARCH=aarch64 \
  --build-arg CANN_CHIP=910b \
  --build-arg CANN_VERSION=9.0.0 \
  --build-arg CANN_RUNFILE=Ascend-cann_9.0.0_linux-aarch64.run \
  --build-arg CANN_OPS_RUNFILE=Ascend-cann-910b-ops_9.0.0_linux-aarch64.run \
  --build-arg CANN_NNAL_RUNFILE= \
  --build-arg TORCH_VERSION=2.10 \
  --build-arg TORCH_NPU_VERSION=2.10 \
  --build-arg TRITON_ASCEND_VERSION=3.2.1 \
  dev-base
```

如需安装全部 framework 包：

```bash
DOCKER_BUILDKIT=1 docker build \
  --platform=linux/arm64 \
  -f dev-framework/Dockerfile \
  -t ascend-cann900-aarch64-tuna:framework \
  --build-arg BASE_IMAGE=ascend-cann900-aarch64-tuna:base \
  --build-arg INSTALL_VLLM=1 \
  --build-arg INSTALL_VLLM_ASCEND=1 \
  --build-arg INSTALL_MEGATRON_MINDSPEED=1 \
  --build-arg INSTALL_VERL=1 \
  --build-arg INSTALL_RLLM=1 \
  --build-arg INSTALL_KERNELGYM=1 \
  dev-framework
```

## 3. 无代理 + 清华源 + CANN 8.5.2

`8.5.2` 复用无代理和清华源配置。当前旧版 Dockerfile 里 `8.5.2` 用过 `triton-ascend 3.2.0`，这里也固定到 `3.2.0`，避免和旧环境产生不必要差异。

```bash
DOCKER_BUILDKIT=1 docker build \
  --platform=linux/arm64 \
  -f dev-base/Dockerfile \
  -t ascend-cann852-aarch64-tuna:base \
  --build-arg BASE_IMAGE=python:3.11-bookworm \
  --build-arg HTTP_PROXY= \
  --build-arg HTTPS_PROXY= \
  --build-arg NO_PROXY= \
  --build-arg DEBIAN_MIRROR_HOST=mirrors.tuna.tsinghua.edu.cn \
  --build-arg APT_DIRECT_HOSTS= \
  --build-arg APT_INSECURE=0 \
  --build-arg DOCKER_APT_BASE=https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian \
  --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
  --build-arg PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn \
  --build-arg CANN_ARCH=aarch64 \
  --build-arg CANN_CHIP=910b \
  --build-arg CANN_VERSION=8.5.2 \
  --build-arg CANN_RUNFILE=Ascend-cann-toolkit_8.5.2_linux-aarch64.run \
  --build-arg CANN_OPS_RUNFILE=Ascend-cann-910b-ops_8.5.2_linux-aarch64.run \
  --build-arg CANN_NNAL_RUNFILE=Ascend-cann-nnal_8.5.2_linux-aarch64.run \
  --build-arg TORCH_VERSION=2.10 \
  --build-arg TORCH_NPU_VERSION=2.10 \
  --build-arg TRITON_ASCEND_VERSION=3.2.0 \
  dev-base
```

如需安装全部 framework 包：

```bash
DOCKER_BUILDKIT=1 docker build \
  --platform=linux/arm64 \
  -f dev-framework/Dockerfile \
  -t ascend-cann852-aarch64-tuna:framework \
  --build-arg BASE_IMAGE=ascend-cann852-aarch64-tuna:base \
  --build-arg INSTALL_VLLM=1 \
  --build-arg INSTALL_VLLM_ASCEND=1 \
  --build-arg INSTALL_MEGATRON_MINDSPEED=1 \
  --build-arg INSTALL_VERL=1 \
  --build-arg INSTALL_RLLM=1 \
  --build-arg INSTALL_KERNELGYM=1 \
  dev-framework
```

## 运行容器

如果只是快速进入完整 framework 镜像，可以用下面模板。镜像名替换为上面构建出的 `*:framework`。

```bash
docker run -it \
  --name ascend-dev \
  --net=host \
  --ipc=host \
  --shm-size=768g \
  --privileged \
  -v /dev:/dev \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /usr/local/dcmi:/usr/local/dcmi:ro \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ascend-cann900-aarch64-tuna:framework \
  bash
```

如果不想安装全部 framework 包，把对应开关改成 `0` 即可，例如只保留 `vllm` 和 `vllm-ascend`：

```bash
--build-arg INSTALL_MEGATRON_MINDSPEED=0
--build-arg INSTALL_VERL=0
--build-arg INSTALL_RLLM=0
--build-arg INSTALL_KERNELGYM=0
```
