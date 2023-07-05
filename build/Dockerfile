ARG CUDA_VERSION=11.8.0
ARG CUDA_TYPE="base"
ARG UBUNTU_VERSION=22.04

# Ensure Nvidia container toolkit
FROM nvidia/cuda:${CUDA_VERSION}-${CUDA_TYPE}-ubuntu${UBUNTU_VERSION}

LABEL org.opencontainers.image.source https://github.com/ai-dock/base-image

LABEL org.opencontainers.image.description "Base image for ai-dock"

# Set ENV variables
ENV LANG C.UTF-8
ENV SHELL=/bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/base/bin:/opt/micromamba/bin:$PATH
ENV APT_INSTALL="apt-get install -y --no-install-recommends"
ENV MAMBA_CREATE="micromamba --experimental create -y -c conda-forge -c defaults"
ENV PIP_INSTALL="pip --no-cache-dir install"
ENV RCLONE_CONFIG="/etc/rclone/rclone.conf"
ENV MAMBA_BASE_ENV="system"
ENV MAMBA_BASE_RUN="micromamba run -n $MAMBA_BASE_ENV"

ARG MAMBA_BASE_PYTHON_VERSION=3.10
ENV MAMBA_BASE_PYTHON_VERSION=${MAMBA_BASE_PYTHON_VERSION}

# Minimal ubuntu base. We will be using conda-forge via micromamba to manage most of our packages. Avoid adding anything with a python dependency
RUN apt-get update && \
    $APT_INSTALL \
        bzip2 \
        zip \
        unzip \
        curl \
        wget \
        nano \
        less \
        screen \
        tmux \
        fuse3 \
        openssh-server \
        libcap2-bin && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    touch /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys && \
    mkdir -p /run/sshd && \
    chmod 700 /run/sshd && \
    rm /etc/update-motd.d/10-help-text && \
    rm /etc/update-motd.d/60-unminimize && \
    mkdir -p /opt/micromamba && \
    cd /opt/micromamba && \
    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj bin/micromamba && \
    micromamba shell init --shell bash --root-prefix=~/micromamba

# Create base conda-forge environment. 
# Increased image size but micromamba is configured to create hardlinks so subsequent environments will be smaller.
RUN $MAMBA_CREATE -n $MAMBA_BASE_ENV python=${MAMBA_BASE_PYTHON_VERSION} && \
    micromamba -n $MAMBA_BASE_ENV install -y -c conda-forge \
        supervisor \
        rclone && \
    mkdir -p /var/log/supervisor && \
    mkdir -p /etc/rclone && \
    touch /etc/rclone/rclone.conf

ADD ./opt /opt
ADD ./etc /etc

EXPOSE 22

ENTRYPOINT [ "entrypoint.sh" ]

CMD ["supervisord-init.sh"]
