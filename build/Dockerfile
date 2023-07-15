# For build automation - Allows building from any Debian-based image
ARG IMAGE_BASE="nvidia/cuda:11.8.0-base-ubuntu22.04"

FROM $IMAGE_BASE

LABEL org.opencontainers.image.source https://github.com/ai-dock/base-image

LABEL org.opencontainers.image.description "Base image for ai-dock."

# Set ENV variables
ENV LANG C.UTF-8
ENV SHELL=/bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/ai-dock/bin:/opt/micromamba/bin:$PATH
ENV APT_INSTALL="apt install -y --no-install-recommends"
ENV MAMBA_CREATE="micromamba --experimental create -y -c conda-forge -c defaults"
ENV PIP_INSTALL="pip --no-cache-dir install"
ENV RCLONE_CONFIG="/etc/rclone/rclone.conf"
ENV MAMBA_BASE_ENV="system"
ENV MAMBA_BASE_RUN="micromamba run -n $MAMBA_BASE_ENV"

# Minimal ubuntu base. We will be using conda-forge via micromamba to manage most of our packages. Avoid adding anything with a python dependency.
RUN apt update && \
    apt upgrade -y --no-install-recommends && \
    $APT_INSTALL \
        acl \
        bzip2 \
        curl \
        fuse3 \
        git \
        less \
        libcap2-bin \
        nano \
        openssh-server \
        screen \
        tmux \
        unzip \
        vim \
        wget \
        zip && \
    apt clean -y && \
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

# System python version just needs to support latest supervisor version. We never want to use it to run additional software.
ARG MAMBA_BASE_PYTHON_VERSION=3.10
ENV MAMBA_BASE_PYTHON_VERSION=${MAMBA_BASE_PYTHON_VERSION}

# Create base conda-forge environment. 
# Increased image size but micromamba is configured to create hardlinks so subsequent environments will be smaller.

RUN $MAMBA_CREATE -n $MAMBA_BASE_ENV python=${MAMBA_BASE_PYTHON_VERSION} && \
    micromamba -n $MAMBA_BASE_ENV install -y -c conda-forge \
        supervisor \
        rclone && \
    rm -rf /root/micromamba/envs/$MAMBA_BASE_ENV/etc/supervisord* && \
    mkdir -p /var/log/supervisor && \
    mkdir -p /etc/rclone && \
    touch /etc/rclone/rclone.conf && \
    micromamba clean -ay

ADD ./opt /opt
ADD ./etc /etc
ADD ./usr /usr
ADD ./root /root

EXPOSE 22

ENTRYPOINT [ "entrypoint.sh" ]

CMD ["supervisord-init.sh"]
