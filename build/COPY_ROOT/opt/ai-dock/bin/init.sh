#!/bin/bash

# Allows passing environment vars through cmd args for when we don't have full control over `docker run...` and cannot pass -e
# docker run ... supervisord-env.sh SOME_VAR="some value"...
# Also allows killing the container from inside.


trap cleanup EXIT

function cleanup() {
    printf "Cleaning up...\n"
    # Each running process should have its own cleanup routine
    wait -n
    $MAMBA_BASE_RUN supervisorctl stop all
    kill -9 "$(cat /var/run/supervisord.pid)"
    rm /var/run/supervisord.pid
    rm /var/run/supervisor.sock
}

function main() {
    set_envs "$@"
    set_ssh_keys
    count_gpus
    set_workspace
    mount_rclone_remotes
    cloud_fixes
    run_preflight_script
    write_bashrc
    
    # Killing supervisord will stop/force restart the container
    wait -n
    $MAMBA_BASE_RUN supervisord -c /etc/supervisor/supervisord.conf
}

function set_envs() {
    for i in "$@"; do
        IFS="=" read -r key val <<< "$i"
        if [[ -n $key && -n $val ]]; then
            export "${key}"="${val}"
        fi
    done
    
    # Replace ___ with a space; Issue fixed by vast but just in case
    while IFS='=' read -r -d '' key val; do
        export "${key}"="${val//___/' '}"
    done < <(env -0)
}

function set_ssh_keys() {
    if [[ -f "/root/.ssh/authorized_keys_mount" ]]; then
        cat /root/.ssh/authorized_keys_mount > /root/.ssh/authorized_keys
    fi
    
    # Named to avoid conflict with the cloud providers below
    if [[ -n $SSH_PUBKEY ]]; then
        printf "%s\n" "$SSH_PUBKEY" >> /root/.ssh/authorized_keys
    fi
    
    # Alt names for $SSH_PUBKEY
    # runpod.io
    if [[ -n $PUBLIC_KEY ]]; then
        printf "%s\n" "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
    fi
    
    # vast.ai
    if [[ -n $SSH_PUBLIC_KEY ]]; then
        printf "%s\n" "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
    fi
}

function count_gpus() {
    nvidia_dir="/proc/driver/nvidia/gpus/"
    if [[ -z $GPU_COUNT ]]; then
        if [[ "$XPU_TARGET" == "NVIDIA_GPU" && -d "$nvidia_dir" ]]; then
            GPU_COUNT="$(echo "$(find "$nvidia_dir" -maxdepth 1 -type d | wc -l)"-1 | bc)"
            export GPU_COUNT
        # TODO FIXME
        elif [[ "$XPU_TARGET" == "AMD_GPU" ]]; then
            export GPU_COUNT=1
        else
            export GPU_COUNT=0
        fi
    fi
}

function set_workspace() {
    if [[ -z $WORKSPACE ]]; then
        export WORKSPACE="/workspace/"
    else
        ws_tmp="/$WORKSPACE/"
        export WORKSPACE=${ws_tmp//\/\//\/}
    fi

    mkdir -p "${WORKSPACE}"remote/.cache
    
    # Determine workspace mount status
    if mountpoint "$WORKSPACE"; then
        export WORKSPACE_MOUNTED=true
    else
        export WORKSPACE_MOUNTED=false
        touch /"${WORKSPACE}"/WARNING-NO-MOUNT.txt
        printf "This directory is not a mounted volume.\n\nData saved here will not survive if the container is destroyed.\n" > "${WORKSPACE}WARNING-NO-MOUNT.txt"
    fi
    
    # Ensure the workspace owner can access files from outside of the container
    WORKSPACE_UID=$(stat -c '%u' "$WORKSPACE")
    export WORKSPACE_UID
    WORKSPACE_GID=$(stat -c '%g' "$WORKSPACE")
    export WORKSPACE_GID
    if [[ -z $SKIP_ACL ]]; then
        setfacl -d -m u:"${WORKSPACE_UID}":rwx "${WORKSPACE}"
        setfacl -d -m m:rwx "${WORKSPACE}"
    fi
}

function mount_rclone_remotes() {
    # Determine if rclone mount will be possible
    capsh --print | grep "Current:" | grep -q cap_sys_admin
    if [[ $? -ne 0 || ! -f /dev/fuse ]]; then
        # Not in container with sufficient privileges
        printf "Environment unsuitable for rclone mount...\n"
        printf "rclone remains available via CLI\n"
        export RCLONE_MOUNT_COUNT=0
    else
        RCLONE_MOUNT_COUNT=$(micromamba run -n "$MAMBA_BASE_ENV" rclone listremotes |wc -w)
        export RCLONE_MOUNT_COUNT
    fi
}

function cloud_fixes() {
    # Don't run tmux automatically on vast.ai
    touch /root/.no_auto_tmux
}

function run_preflight_script() {
    # Child images can provide in their PATH
    printf "Looking for preflight.sh...\n"
    if ! which preflight.sh; then
        printf "Not found\n"
    else
        preflight.sh
    fi
}

function write_bashrc() {
    # Ensure all variables available for interactive sessions
    while IFS='=' read -r -d '' key val; do
        printf "export %s=\"%s\"\n" "$key" "$val" >> /root/.bashrc
    done < <(env -0)
}

main "$@"; exit
