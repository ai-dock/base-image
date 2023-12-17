#!/bin/false

export MAMBA_CREATE="micromamba create --always-softlink -y -c conda-forge"
export MAMBA_INSTALL="micromamba install --always-softlink -y -c conda-forge"
printf "export MAMBA_CREATE=\"%s\"\n" "${MAMBA_CREATE}" >> /opt/ai-dock/etc/environment.sh
printf "export MAMBA_INSTALL=\"%s\"\n" "${MAMBA_INSTALL}" >> /opt/ai-dock/etc/environment.sh

apt-get update
apt-get upgrade -y --no-install-recommends

# System packages
$APT_INSTALL \
    acl \
    bc \
    build-essential \
    bzip2 \
    ca-certificates \
    curl \
    dos2unix \
    fuse3 \
    git \
    git-lfs \
    gpg \
    inotify-tools \
    jq \
    less \
    libcap2-bin \
    libelf1 \
    libglib2.0-0 \
    lsb-release \
    lsof \
    nano \
    openssh-server \
    python3-pip \
    rclone \
    rsync \
    screen \
    supervisor \
    tmux \
    unzip \
    vim \
    wget \
    xz-utils \
    zip
  
  # These libraries are needed to run the log/redirect interfaces
  # They are needed before micromamba is guaranteed to be ready
  $PIP_INSTALL \
    bcrypt \
    uvicorn==0.23 \
    fastapi==0.103 \
    jinja2==3.1 \
    jinja_partials \
    python-multipart \
    websockets

# Get caddy server
mkdir -p /opt/caddy/bin
wget -c -O caddy.tar.gz https://github.com/caddyserver/caddy/releases/download/v2.7.5/caddy_2.7.5_linux_amd64.tar.gz 
tar -xf caddy.tar.gz -C /opt/caddy
rm caddy.tar.gz
mv /opt/caddy/caddy /opt/caddy/bin

# Get Cloudflare daemon
wget -c -O cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb
rm cloudflared.deb

# Prepare environment for running SSHD
chmod 700 /root
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Remove less relevant parts of motd
rm /etc/update-motd.d/10-help-text
rm /etc/update-motd.d/60-unminimize

# Install micromamba (conda replacement)
mkdir -p /opt/micromamba
cd /opt/micromamba
curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj bin/micromamba
micromamba shell init --shell bash --root-prefix=/opt/micromamba

# Ensure critical paths/files are present
mkdir -p --mode=0755 /etc/apt/keyrings
mkdir -p /var/log/supervisor
mkdir -p /run/sshd
mkdir -p /var/empty
mkdir -p /etc/rclone
touch /etc/rclone/rclone.conf

# Git config

git config --global --add safe.directory "*"

# Ensure correct environment for child builds

printf "source /opt/ai-dock/etc/environment.sh\n" >> /etc/profile.d/02-ai-dock.sh
printf "source /opt/ai-dock/etc/environment.sh\n" >> /etc/bash.bashrc