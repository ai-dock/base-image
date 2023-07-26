# For build automation - Allows building from any Debian-based image
ARG IMAGE_BASE="nvidia/cuda:11.8.0-base-ubuntu22.04"
FROM ${IMAGE_BASE}

# Determines which scripts at /opt/ai-dock/bin/build/layerX will be run by init.sh
ARG XPU_TARGET="GPU_NVIDIA" # GPU_AMD, CPU
ENV XPU_TARGET=${XPU_TARGET}

LABEL org.opencontainers.image.source https://github.com/ai-dock/base-image

LABEL org.opencontainers.image.description "Base image for ai-dock."

LABEL maintainer="Rob Ballantyne <rob@dynamedia.uk>"

# Set ENV variables
ENV LANG C.UTF-8
ENV SHELL=/bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/ai-dock/bin:/opt/micromamba/bin:$PATH
ENV APT_INSTALL="apt-get install -y --no-install-recommends"
ENV MAMBA_CREATE="micromamba --experimental create -y -c conda-forge -c defaults"
ENV RCLONE_CONFIG="/etc/rclone/rclone.conf"
ENV MAMBA_BASE_ENV="system"
ENV MAMBA_BASE_RUN="micromamba run -n $MAMBA_BASE_ENV"
ARG MAMBA_BASE_PYTHON_VERSION=3.10
ENV MAMBA_BASE_PYTHON_VERSION=${MAMBA_BASE_PYTHON_VERSION}
# Copy early so we can use scripts in the build - Changes to these files will invalidate the cache and cause a rebuild.
COPY ./COPY_ROOT/ /

# Env these args - We need them to ease software installation in extended images
ARG CUDA_VERSION
ENV CUDA_VERSION=${CUDA_VERSION}
ARG CUDNN_VERSION
ENV CUDNN_VERSION=${CUDNN_VERSION}
ARG CUDA_LEVEL
ENV CUDA_LEVEL=${CUDA_LEVEL}
ARG ROCM_VERSION
ENV ROCM_VERSION=${ROCM_VERSION}
ARG ROCM_LEVEL
ENV ROCM_LEVEL=${ROCM_LEVEL}

# Use build scripts to ensure we can build all targets from one Dockerfile in a single layer.
# Don't put anything heavy in here - We can use multi-stage building above if necessary.
RUN bash -c /opt/ai-dock/bin/build/layer0/init.sh

ENTRYPOINT [ "entrypoint.sh" ]

CMD ["supervisord-init.sh"]
