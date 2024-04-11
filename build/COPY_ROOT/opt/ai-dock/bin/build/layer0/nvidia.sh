#!/bin/false

export CUDA_VERSION="${CUDA_VERSION}"
env-store CUDA_VERSION
export CUDNN_VERSION="${CUDNN_VERSION}"
env-store CUDNN_VERSION
export CUDA_LEVEL="${CUDA_LEVEL}"
env-store CUDA_LEVEL
export CUDA_STRING="$(cut -d '.' -f 1,2 <<< "${CUDA_VERSION}")"
env-store CUDA_STRING