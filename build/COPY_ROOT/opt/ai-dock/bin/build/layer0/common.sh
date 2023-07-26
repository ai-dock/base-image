#!/bin/bash

# Must exit and fail to build if any command fails
set -e

apt-get update
apt-get upgrade -y --no-install-recommends

# A minimal collection of packages.
$APT_INSTALL \
    acl \
    bzip2 \
    ca-certificates \
    curl \
    fuse3 \
    git \
    gpg \
    less \
    libcap2-bin \
    libelf1 \
    lsb-release \
    nano \
    openssh-server \
    screen \
    tmux \
    unzip \
    vim \
    zip

# Prepare environment for running SSHD
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
mkdir -p /run/sshd
chmod 700 /run/sshd

# Remove less relevant parts of motd
rm /etc/update-motd.d/10-help-text
rm /etc/update-motd.d/60-unminimize

# Install micromamba (conda replacement)
mkdir -p /opt/micromamba
cd /opt/micromamba
curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj bin/micromamba
micromamba shell init --shell bash --root-prefix=~/micromamba

# Install the 'system' base micromamba environment
$MAMBA_CREATE -n $MAMBA_BASE_ENV python=${MAMBA_BASE_PYTHON_VERSION}
micromamba -n $MAMBA_BASE_ENV install -y -c conda-forge \
        supervisor \
        rclone
        
# We will use a config from /etc
rm -rf /root/micromamba/envs/$MAMBA_BASE_ENV/etc/supervisord*

# Ensure critical paths/files are present
mkdir -p --mode=0755 /etc/apt/keyrings
mkdir -p /var/log/supervisor
mkdir -p /etc/rclone
touch /etc/rclone/rclone.conf
