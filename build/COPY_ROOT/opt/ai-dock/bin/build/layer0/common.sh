#!/bin/false

groupadd -g 1111 ai-dock
chown root.ai-dock /opt
chmod g+w /opt
chmod g+s /opt

dpkg --add-architecture i386
apt-get update
apt-get upgrade -y --no-install-recommends

# System packages
$APT_INSTALL \
    acl \
    apt-transport-https \
    apt-utils \
    bc \
    build-essential \
    bzip2 \
    ca-certificates \
    curl \
    dnsutils \
    dos2unix \
    fakeroot \
    file \
    fuse3 \
    git \
    git-lfs \
    gnupg \
    gpg \
    gzip \
    htop \
    inotify-tools \
    jq \
    language-pack-en \
    less \
    libcap2-bin \
    libelf1 \
    libglib2.0-0 \
    libgoogle-perftools4 \
    locales \
    lsb-release \
    lsof \
    man \
    mlocate \
    net-tools \
    nano \
    openssh-server \
    pkg-config \
    psmisc \
    python3-pip \
    rar \
    rclone \
    rsync \
    screen \
    software-properties-common \
    ssl-cert \
    sudo \
    supervisor \
    tmux \
    tzdata \
    unar \
    unrar \
    unzip \
    vim \
    wget \
    xz-utils \
    zip \
    zstd
  
locale-gen en_US.UTF-8
    
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
rm -f /etc/update-motd.d/10-help-text

# Install micromamba (conda replacement)
mkdir -p /opt/micromamba
printf "channels: [%sconda-forge]\nalways_softlink: true\n" "${CUDA_VERSION:+nvdia,}"> /opt/micromamba/.mambarc
cd /opt/micromamba
curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj bin/micromamba
micromamba shell init --shell bash --root-prefix=/opt/micromamba

# Ensure critical paths/files are present
mkdir -p --mode=0755 /etc/apt/keyrings
mkdir -p --mode=0755 /run/sshd
chown -R root.ai-dock /var/log
chmod -R g+w /var/log
chmod -R g+s /var/log
mkdir -p /var/log/supervisor
mkdir -p /var/empty
mkdir -p /etc/rclone
touch /etc/rclone/rclone.conf

# Install SyncThing to enable transport between local machine and cloud instance

SYNCTHING_VERSION="$(curl -fsSL "https://api.github.com/repos/syncthing/syncthing/releases/latest" \
            | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"

SYNCTHING_URL="https://github.com/syncthing/syncthing/releases/download/v${SYNCTHING_VERSION}/syncthing-linux-amd64-v${SYNCTHING_VERSION}.tar.gz"
mkdir /opt/syncthing/
wget -O /opt/syncthing.tar.gz $SYNCTHING_URL && (cd /opt && tar -zxf syncthing.tar.gz -C /opt/syncthing/ --strip-components=1) && rm -f /opt/syncthing.tar.gz
ln -s /opt/syncthing/syncthing /opt/ai-dock/bin/syncthing

# Ensure correct environment for child builds

printf "source /opt/ai-dock/etc/environment.sh\n" >> /etc/profile.d/02-ai-dock.sh
printf "source /opt/ai-dock/etc/environment.sh\n" >> /etc/bash.bashrc
printf "ready-test\n" >> /root/.bashrc

# Give our runtime user full access (added to ai-dock group)
/opt/ai-dock/bin/fix-permissions.sh -o container