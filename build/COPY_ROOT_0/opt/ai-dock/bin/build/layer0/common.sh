#!/bin/false

groupadd -g 1111 ai-dock
chown root.ai-dock /opt
chmod g+w /opt
chmod g+s /opt

mkdir -p /opt/environments/{python,javascript}

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
    cmake \
    curl \
    dnsutils \
    dos2unix \
    fakeroot \
    ffmpeg \
    file \
    fonts-dejavu \
    fonts-freefont-ttf \
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
    libgl1-mesa-glx \
    libglib2.0-0 \
    libtcmalloc-minimal4 \
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
    python3 \
    python3-pip \
    python3-venv \
    rar \
    rclone \
    rsync \
    screen \
    software-properties-common \
    sox \
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
    
ln -sf $(ldconfig -p | grep -Po "libtcmalloc_minimal.so.\d" | head -n 1) \
        /lib/x86_64-linux-gnu/libtcmalloc.so

# Ensure deadsnakes is available for Python versions not included with base distribution
add-apt-repository ppa:deadsnakes/ppa
apt update
  
locale-gen en_US.UTF-8

# Install 
python3.10 -m venv /opt/environments/python/serviceportal
/opt/environments/python/serviceportal/bin/pip install \
    --no-cache-dir -r /opt/ai-dock/fastapi/requirements.txt

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

export SYNCTHING_VERSION="$(curl -fsSL "https://api.github.com/repos/syncthing/syncthing/releases/latest" \
            | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
env-store SYNCTHING_VERSION

SYNCTHING_URL="https://github.com/syncthing/syncthing/releases/download/v${SYNCTHING_VERSION}/syncthing-linux-amd64-v${SYNCTHING_VERSION}.tar.gz"
mkdir /opt/syncthing/
wget -O /opt/syncthing.tar.gz $SYNCTHING_URL && (cd /opt && tar -zxf syncthing.tar.gz -C /opt/syncthing/ --strip-components=1) && rm -f /opt/syncthing.tar.gz
ln -s /opt/syncthing/syncthing /opt/ai-dock/bin/syncthing

# Install node version manager and latest nodejs
export NVM_DIR=/opt/nvm
env-store NVM_DIR
git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
(cd "$NVM_DIR" && git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`)
source $NVM_DIR/nvm.sh
nvm install $NODE_VERSION
nvm alias default $NODE_VERSION

# Ensure correct environment for child builds
printf "source %s/nvm.sh\n" "$NVM_DIR" >> /opt/ai-dock/etc/environment.sh
printf "source %s/bash_completion\n" "$NVM_DIR" >> /opt/ai-dock/etc/environment.sh
printf "source /opt/ai-dock/etc/environment.sh\n" >> /etc/profile.d/02-ai-dock.sh
printf "source /opt/ai-dock/etc/environment.sh\n" >> /etc/bash.bashrc
printf "ready-test\n" >> /root/.bashrc

# Give our runtime user full access (added to ai-dock group)
/opt/ai-dock/bin/fix-permissions.sh -o container