# For build automation - Allows building from any Debian-based image
ARG IMAGE_BASE="nvidia/cuda:11.8.0-base-ubuntu22.04"
FROM ${IMAGE_BASE}

# Determines which scripts at /opt/ai-dock/bin/build/layerX will be run by init.sh
ARG XPU_TARGET="GPU_NVIDIA" # GPU_AMD, CPU
ENV XPU_TARGET=${XPU_TARGET}

LABEL org.opencontainers.image.source https://github.com/ai-dock/base-image

LABEL org.opencontainers.image.description "Base image for ai-dock."

LABEL maintainer="Rob Ballantyne <rob@dynamedia.uk>"

SHELL ["/bin/bash", "-c"]
# Set ENV variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TZ=UTC
ENV SHELL="/bin/bash"
ENV USER_NAME=user
ENV USER_GROUPS=users,adm,sudo,audio,video,tty
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/ai-dock/bin:/opt/micromamba/bin:/opt/caddy/bin:$PATH
ENV OPT_SYNC=
ENV PYTHONUNBUFFERED=true
ENV APT_INSTALL="apt-get install -y --no-install-recommends"
ENV PIP_INSTALL="pip install --no-cache-dir"
ENV MAMBA_ROOT_PREFIX=/opt/micromamba
ENV MAMBA_EXE="/opt/micromamba/bin/micromamba"
ENV RCLONE_CONFIG="/etc/rclone/rclone.conf"
ENV IMAGE_SLUG="base-image"
# Copy early so we can use scripts in the build - Changes to these files will invalidate the cache and cause a rebuild.
COPY ./COPY_ROOT/ /

ARG CUDA_VERSION
ARG CUDNN_VERSION
ARG CUDA_LEVEL
ARG ROCM_VERSION
ARG ROCM_LEVEL

# Use build scripts to ensure we can build all targets from one Dockerfile in a single layer.
# Don't put anything heavy in here - We can use multi-stage building above if necessary.
RUN yes | unminimize && \
    set -eo pipefail && /opt/ai-dock/bin/build/layer0/init.sh | tee /var/log/build.log

# Copy overrides and new files into a final layer for fast rebuilds. Uncomment below
#COPY ./COPY_ROOT_EXTRA/ /
#RUN set -eo pipefail && /opt/ai-dock/bin/build/layer1/init.sh | tee -a /var/log/build.log

# Keep init.sh as-is and place additional logic in /opt/ai-dock/bin/preflight.sh
CMD ["init.sh"]
