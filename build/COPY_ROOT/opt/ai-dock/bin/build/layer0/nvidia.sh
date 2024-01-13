#!/bin/false

export CUDA_VERSION=${CUDA_VERSION}
env-store CUDA_VERSION
export CUDNN_VERSION=${CUDNN_VERSION}
env-store CUDNN_VERSION
export CUDA_LEVEL=${CUDA_LEVEL}
env-store CUDA_LEVEL
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
env-store LD_LIBRARY_PATH
export MAMBA_CREATE="micromamba create --always-softlink -y -c nvidia -c conda-forge"
env-store MAMBA_CREATE
export MAMBA_INSTALL="micromamba install --always-softlink -y -c nvidia -c conda-forge"
env-store MAMBA_INSTALL
