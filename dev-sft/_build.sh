#!/bin/bash
set -x
cd /home/sunzhihao/rllm-env
export DOCKER_BUILDKIT=0
docker build -t qwen36sft:latest -f dev-sft/Dockerfile \
  --build-arg BASE_IMAGE=ascend-cann900-aarch64-tuna:base \
  --build-arg FLA_BUILD_MODE=prebuilt \
  dev-sft
echo "BUILD_EXIT_CODE=$?"
