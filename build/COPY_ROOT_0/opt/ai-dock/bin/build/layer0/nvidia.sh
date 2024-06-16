#!/bin/false

if [[ -z $CUDA_STRING ]]; then
    printf "No valid CUDA_STRING specified\n" >&2
    exit 1
fi

export CUDA_VERSION=$(printf "%s" "$CUDA_STRING" | cut -d'-' -f1)
env-store CUDA_VERSION
export CUDA_LEVEL=$(printf "%s" "$CUDA_STRING" | cut -d'-' -f2)
env-store CUDA_LEVEL

# Ensure nvcc available on all bases
cuda_version_dash=$(echo "$CUDA_VERSION" | sed -E 's/\.[^.]*$//; s/\./-/g')
if [[ ! $CUDA_LEVEL == *devel* ]]; then
    $APT_INSTALL "cuda-nvcc-$cuda_version_dash"
fi
