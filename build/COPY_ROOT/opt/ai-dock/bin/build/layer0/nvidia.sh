#!/bin/false

export CUDA_VERSION=${CUDA_VERSION}
export CUDNN_VERSION=${CUDNN_VERSION}
export CUDA_LEVEL=${CUDA_LEVEL}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
export MAMBA_CREATE="micromamba create --always-softlink -y -c nvidia -c conda-forge"
export MAMBA_INSTALL="micromamba install --always-softlink -y -c nvidia -c conda-forge"
printf "export CUDA_VERSION=\"%s\"\n" "${CUDA_VERSION}" >> /opt/ai-dock/etc/environment.sh
printf "export CUDNN_VERSION=\"%s\"\n" "${CUDNN_VERSION}" >> /opt/ai-dock/etc/environment.sh
printf "export CUDA_LEVEL=\"%s\"\n" "${CUDA_LEVEL}" >> /opt/ai-dock/etc/environment.sh
printf "export LD_LIBRARY_PATH=\"%s\"\n" "${LD_LIBRARY_PATH}" >> /opt/ai-dock/etc/environment.sh
printf "export MAMBA_CREATE=\"%s\"\n" "${MAMBA_CREATE}" >> /opt/ai-dock/etc/environment.sh
printf "export MAMBA_INSTALL=\"%s\"\n" "${MAMBA_INSTALL}" >> /opt/ai-dock/etc/environment.sh
