#!/bin/false

export CUDA_VERSION=$(printf "%s" "$CUDA_STRING" | cut -d'-' -f1)
env-store CUDA_VERSION
export CUDA_LEVEL=$(printf "%s" "$CUDA_STRING" | cut -d'-' -f2)
env-store CUDA_LEVEL

