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
SHELL ["/bin/bash", "-c"]
ENV SHELL="/bin/bash"
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/ai-dock/bin:/opt/micromamba/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
ENV PYTHONUNBUFFERED=true
ENV APT_INSTALL="apt-get install -y --no-install-recommends"
ENV PIP_INSTALL="pip install --no-cache-dir"
ENV MAMBA_CREATE="micromamba create --always-softlink -y"
ENV MAMBA_INSTALL="micromamba install --always-softlink -y"
ENV MAMBA_ROOT_PREFIX=/opt/micromamba
ENV MAMBA_EXE="/opt/micromamba/bin/micromamba"
ENV MAMBA_BASE_ENV="system"
ENV MAMBA_BASE_RUN="micromamba run -n $MAMBA_BASE_ENV"
ARG MAMBA_DEFAULT_ENV="system"
ENV MAMBA_DEFAULT_ENV=${MAMBA_DEFAULT_ENV}
ENV MAMBA_DEFAULT_RUN="micromamba run -n $MAMBA_DEFAULT_ENV"
ARG MAMBA_BASE_PYTHON_VERSION=3.10
ENV MAMBA_BASE_PYTHON_VERSION=${MAMBA_BASE_PYTHON_VERSION}
ENV RCLONE_CONFIG="/etc/rclone/rclone.conf"
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

ENV IMAGE_SLUG="base-image"
# Use build scripts to ensure we can build all targets from one Dockerfile in a single layer.
# Don't put anything heavy in here - We can use multi-stage building above if necessary.
RUN /opt/ai-dock/bin/build/layer0/init.sh

# Keep init.sh as-is and place additional logic in /opt/ai-dock/bin/preflight.sh
CMD ["init.sh"]
