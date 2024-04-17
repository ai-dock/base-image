#!/bin/false

if [[ -z $CUDA_STRING ]]; then
    printf "No valid CUDA_STRING specified\n" >&2
    exit 1
fi

export CUDA_VERSION=$(printf "%s" "$CUDA_STRING" | cut -d'-' -f1)
env-store CUDA_VERSION
export CUDA_LEVEL=$(printf "%s" "$CUDA_STRING" | cut -d'-' -f2)
env-store CUDA_LEVEL

