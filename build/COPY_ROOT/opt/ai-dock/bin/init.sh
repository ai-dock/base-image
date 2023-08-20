#!/bin/bash

trap init_cleanup EXIT

function init_cleanup() {
    printf "Cleaning up...\n"
    # Each running process should have its own cleanup routine
    $MAMBA_BASE_RUN supervisorctl stop all
    kill -9 $(cat /var/run/supervisord.pid) > /dev/null 2>&1
    rm /var/run/supervisord.pid
    rm /var/run/supervisor.sock
}

function init_main() {
    init_set_envs "$@"
    init_set_ssh_keys
    init_count_gpus
    init_set_workspace
    init_mount_rclone_remotes
    init_cloud_fixes
    init_source_preflight_script
    init_get_provisioning_script
    init_source_provisioning_script
    init_write_bashrc
    init_debug_print
    
    # Killing supervisord will stop/force restart the container
    $MAMBA_BASE_RUN supervisord -c /etc/supervisor/supervisord.conf
}

function init_set_envs() {
    for i in "$@"; do
        IFS="=" read -r key val <<< "$i"
        if [[ -n $key && -n $val ]]; then
            export "${key}"="${val}"
        fi
    done
    
    # Re-write envs; Strip quotes & replace ___ with a space
    while IFS='=' read -r -d '' key val; do
        export "${key}"="$(init_strip_quotes "${val//___/' '}")"
    done < <(env -0)
    
    # TODO: branch init.sh into common,nvidia,amd,cpu
    if [[ $XPU_TARGET == "AMD_GPU" ]]; then
            export PATH=$PATH:/opt/rocm/bin
    fi
}

function init_set_ssh_keys() {
    if [[ -f "/root/.ssh/authorized_keys_mount" ]]; then
        cat /root/.ssh/authorized_keys_mount > /root/.ssh/authorized_keys
    fi
    
    # Named to avoid conflict with the cloud providers below
    
    if [[ -n $SSH_PUBKEY ]]; then
        printf "\n%s\n" "$SSH_PUBKEY" >> /root/.ssh/authorized_keys
    fi
    
    # Alt names for $SSH_PUBKEY
    # runpod.io
    if [[ -n $PUBLIC_KEY ]]; then
        printf "\n%s\n" "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
    fi
    
    # vast.ai
    if [[ -n $SSH_PUBLIC_KEY ]]; then
        printf "\n%s\n" "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
    fi
}

function init_count_gpus() {
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

function init_set_workspace() {
    if [[ -z $WORKSPACE ]]; then
        export WORKSPACE="/workspace/"
    else
        ws_tmp="/$WORKSPACE/"
        export WORKSPACE=${ws_tmp//\/\//\/}
    fi

    mkdir -p "${WORKSPACE}"remote/.cache
    
    # Determine workspace mount status
    if mountpoint "$WORKSPACE" > /dev/null 2>&1; then
        export WORKSPACE_MOUNTED=true
    else
        export WORKSPACE_MOUNTED=false
        no_mount_warning_file="${WORKSPACE}WARNING-NO-MOUNT.txt"
        no_mount_warning="$WORKSPACE is not a mounted volume.\n\nData saved here will not survive if the container is destroyed.\n"
        printf "%b" "${no_mount_warning}"
        touch "${no_mount_warning_file}"
        printf "%b" "${no_mount_warning}" > "${no_mount_warning_file}"
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

function init_mount_rclone_remotes() {
    # Determine if rclone mount will be possible
    mount_env_warning_file="${WORKSPACE}remote/WARNING-CANNOT-MOUNT-REMOTES.txt"
    no_remotes_warning_file="${WORKSPACE}remote/WARNING-NO-REMOTES-CONFIGURED.txt"
    rm ${mount_env_warning_file} > /dev/null 2>&1
    rm ${no_remotes_warning_file} > /dev/null 2>&1
    capsh --print | grep "Current:" | grep -q cap_sys_admin
    if [[ $? -ne 0 || ! -e /dev/fuse ]]; then
        # Not in container with sufficient privileges
        mount_env_warning="Environment unsuitable for rclone mount...\nrclone remains available via CLI\n"
        printf "%b" "${mount_env_warning}"
        touch "${mount_env_warning_file}"
        printf "%b" "${mount_env_warning}" > "${mount_env_warning_file}"
        export RCLONE_MOUNT_COUNT=0
    else
        RCLONE_MOUNT_COUNT=$(micromamba run -n "$MAMBA_BASE_ENV" rclone listremotes |wc -w)
        export RCLONE_MOUNT_COUNT
        if [[ $RCLONE_MOUNT_COUNT -eq 0 ]]; then
            no_remotes_warning="You have no configured rclone remotes to be mounted\n"
            printf "%b" "${no_remotes_warning}"
            touch "${no_remotes_warning_file}"
            printf "%b" "${no_remotes_warning}" > ${no_remotes_warning_file}
        fi
    fi
}

function init_cloud_fixes() {
    # Don't run tmux automatically on vast.ai
    if [[ -n $VAST_NO_TMUX ]]; then
        touch /root/.no_auto_tmux
    fi
}

function init_source_preflight_script() {
    # Child images can provide in their PATH
    printf "Looking for preflight.sh...\n"
    if [[ ! -f /opt/ai-dock/bin/preflight.sh ]]; then
        printf "Not found\n"
    else
        source /opt/ai-dock/bin/preflight.sh
    fi
}

function init_write_bashrc() {
    # Ensure all variables available for interactive sessions
    env > /etc/environment
    while IFS='=' read -r -d '' key val; do
        printf "export %s=\"%s\"\n" "$key" "$val" >> /root/.bashrc
    done < <(env -0)
    
    a='alias rclone="micromamba run -n system rclone"'
    printf "%s\n" "$a" >> /root/.bashrc
    
    a='alias supervisorctl="micromamba run -n system supervisorctl -c /etc/supervisor/supervisord.conf"'
    printf "%s\n" "$a" >> /root/.bashrc
    
    a='alias supervisord="micromamba run -n system supervisord -c /etc/supervisor/supervisord.conf"'
    printf "%s\n" "$a" >> /root/.bashrc
    
    printf "micromamba activate %s\n" $MAMBA_DEFAULT_ENV >> /root/.bashrc
    
    printf "cd %s\n" "$WORKSPACE" >> /root/.bashrc
}

function init_get_provisioning_script() {
    if [[ -n  $PROVISIONING_SCRIPT ]]; then
        file="/opt/ai-dock/bin/provisioning.sh"
        set +e
        curl -L -o ${file} ${PROVISIONING_SCRIPT}
        if [[ "$?" -eq 0 ]]; then
            printf "Successfully created %s from %s\n" "$file" "$PROVISIONING_SCRIPT"
        else
            printf "Failed to fetch %s\n" "$PROVISIONING_SCRIPT"
            rm $file > /dev/null 2>&1
        fi
    fi
}

function init_source_provisioning_script() {
    # Child images can provide in their PATH
    printf "Looking for provisioning.sh...\n"
    if [[ ! -f /opt/ai-dock/bin/provisioning.sh ]]; then
        printf "Not found\n"
    else
        source /opt/ai-dock/bin/provisioning.sh
    fi
}

# This could be much better...
function init_strip_quotes() {
    if [[ -z $1 ]]; then
        printf ""
    elif [[ ${1:0:1} = '"' && ${1:(-1)} = '"' ]]; then
        sed -e 's/^.//' -e 's/.$//' <<< "$1"
    elif [[ ${1:0:1} = "'" && ${1:(-1)} = "'" ]]; then
        sed -e 's/^.//' -e 's/.$//' <<< "$1"
    else
        printf "%s" "$1"
    fi
}

function init_debug_print() {
    if [[ -n $DEBUG ]]; then
        printf "\n\n\n---------- DEBUG INFO ----------\n\n"
        printf "env output...\n\n"
        env
        printf "\n--------------------------------------------\n"
        printf "authorized_keys...\n\n"
        cat /root/.ssh/authorized_keys
        printf "\n--------------------------------------------\n"
        printf ".bashrc...\n\n"
        cat /root/.bashrc
        printf "\n---------- END DEBUG INFO---------- \n\n\n"
    fi
}

init_main "$@"; exit
