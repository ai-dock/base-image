#!/bin/bash

if [[ -z $WORKSPACE ]]; then
    export WORKSPACE="/workspace/"
else
    ws_tmp="/$WORKSPACE/"
    export WORKSPACE=${ws_tmp//\/\//\/}
fi

mkdir -p ${WORKSPACE}remote/.cache

# Replace ___ with a space. Vast.ai fix
while IFS='=' read -r -d '' key val; do
    export ${key}="${val//___/' '}"
done < <(env -0)

if [[ -z $GPU_COUNT ]]; then
    export GPU_COUNT=$(ls -l /proc/driver/nvidia/gpus/ | grep -c ^d)
fi

if [[ -f "/root/.ssh/authorized_keys_mount" ]]; then
    cat /root/.ssh/authorized_keys_mount > /root/.ssh/authorized_keys
fi

# named to avoid conflict with the cloud providers below
if [[ ! -z $SSH_PUBKEY ]]; then
    printf "$SSH_PUBKEY\n" >> /root/.ssh/authorized_keys
fi

# Alt names for $SSH_PUBKEY
# runpod.io
if [[ ! -z $PUBLIC_KEY ]]; then
    printf "$PUBLIC_KEY\n" >> /root/.ssh/authorized_keys
fi

# vast.ai
if [[ ! -z $SSH_PUBLIC_KEY ]]; then
    printf "$SSH_PUBLIC_KEY\n" >> /root/.ssh/authorized_keys
fi

# Don't run tmux automatically on vast.ai
touch /root/.no_auto_tmux

# Determine workspace mount status
mountpoint $WORKSPACE
if [[ $? -eq 0 ]]; then
    export WORKSPACE_MOUNTED=true
else
    export WORKSPACE_MOUNTED=false
    touch /${WORKSPACE}/WARNING-NO-MOUNT.txt
    printf "This directory is not a mounted volume.\n\nData saved here will not survive if the container is destroyed.\n" > "${WORKSPACE}WARNING-NO-MOUNT.txt"
fi

# Ensure the workspace owner can access files from outside of the container
export WORKSPACE_UID=$(stat -c '%u' $WORKSPACE)
export WORKSPACE_GID=$(stat -c '%g' $WORKSPACE)
if [[ -z $SKIP_ACL ]]; then
    setfacl -R -d -m u:${WORKSPACE_UID}:rwx ${WORKSPACE}
    setfacl -R -d -m m:rwx ${WORKSPACE}
fi

# Determine if rclone mount will be possible
capsh --print | grep "Current:" | grep -q cap_sys_admin
if [[ $? -ne 0 && ! -f /dev/fuse ]]; then
    # Not in container with sufficient privileges
    printf "Environment unsuitable for rclone mount...\n"
    printf "rclone remains available via CLI\n"
    export RCLONE_MOUNT_COUNT=0
else
    export RCLONE_MOUNT_COUNT=$(micromamba run -n $MAMBA_BASE_ENV rclone listremotes |wc -w)
fi

# Ensure all variables available for interactive sessions
while IFS='=' read -r -d '' key val; do
    printf "export %s=\"%s\"\n" "$key" "$val" >> /root/.bashrc
done < <(env -0)

exec "$@"
