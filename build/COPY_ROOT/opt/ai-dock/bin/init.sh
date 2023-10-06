#!/bin/bash

trap init_cleanup EXIT

function init_cleanup() {
    printf "Cleaning up...\n"
    # Each running process should have its own cleanup routine
    supervisorctl stop all
    kill -9 $(cat /var/run/supervisord.pid) > /dev/null 2>&1
    rm /var/run/supervisord.pid
    rm /var/run/supervisor.sock
}

function init_main() {
    init_set_envs "$@"
    init_set_ssh_keys
    init_set_web_credentials
    init_count_gpus
    init_count_quicktunnels
    init_set_workspace
    init_set_cf_tunnel_wanted
    init_mount_rclone_remotes
    init_cloud_context
    init_create_logfiles
    touch /run/provisioning_script
    touch /run/workspace_moving
    # Allow autostart processes to run early
    supervisord -c /etc/supervisor/supervisord.conf &
    # Redirect output to files - Logtail will now handle
    init_move_mamba_envs
    init_move_apps
    rm /run/workspace_moving
    init_source_preflight_script > /var/log/supervisor/preflight.log 2>&1
    init_write_bashrc
    init_debug_print > /var/log/supervisor/debug.log 2>&1
    init_get_provisioning_script > /var/log/supervisor/provisioning.log 2>&1
    init_source_provisioning_script >> /var/log/supervisor/provisioning.log 2>&1
    # Removal of this file will trigger fastapi shutdown and service start
    rm /run/provisioning_script
    # Don't exit unless supervisord is killed
    wait
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

init_set_web_credentials() {
  if [[ -z $WEB_USER ]]; then
     export WEB_USER=user
  fi
  
  if [[ -z $WEB_PASSWORD_HASH ]]; then
      if [[ -z $WEB_PASSWORD ]]; then
          WEB_PASSWORD=password
      fi
      export WEB_PASSWORD_HASH=$(hash-password.sh -p $WEB_PASSWORD -r 15)
      export WEB_PASSWORD="******"
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

function init_count_quicktunnels() {
    mkdir -p /run/http_ports
    if [[ ! $CF_QUICK_TUNNELS = "true" ]]; then
        export CF_QUICK_TUNNELS_COUNT=0
    else
        export CF_QUICK_TUNNELS_COUNT=$(($(grep -l "METRICS_PORT" /opt/ai-dock/bin/supervisor-*.sh | wc -l)+1))
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

function init_move_mamba_envs() {
  if [[ $WORKSPACE_MOUNTED = "false" ]]; then
      printf "No mount: Mamba environments remain in /opt\n"
  elif [[ ${WORKSPACE_SYNC,,} = "false" ]]; then
      printf "Skipping workspace sync: Mamba environments remain in /opt\n"
  elif [[ -f ${WORKSPACE}micromamba/.move_complete ]]; then
      printf "Mamba environments already present at ${WORKSPACE}\n"
      rm -rf /opt/micromamba/*
      link-mamba-envs.sh
  else
      printf "Moving mamba environments to ${WORKSPACE}...\n"
      rm -rf ${WORKSPACE}micromamba
      rsync -az /opt/micromamba ${WORKSPACE} && \
        rm -rf /opt/micromamba/* && \
        echo 1 > ${WORKSPACE}micromamba/.move_complete && \
        link-mamba-envs.sh
  fi
}

init_move_apps() {
  for item in /opt/*; do
    dir="$(basename $item)"
    if [[ ! -d $item || $dir = "ai-dock" || $dir = "caddy" || $dir = "micromamba" ]]; then
        continue
    fi
    
    ws_dir=${WORKSPACE}${dir}
    opt_dir="/opt/${dir}"
    
    if [[ $WORKSPACE_MOUNTED = "true" && ${WORKSPACE_SYNC,,} != "false" ]]; then
        if [[ -d $ws_dir && -L $opt_dir ]]; then
            printf "%s already symlinked to %s\n" $opt_dir $ws_dir
        else
            if [[ -L $ws_dir ]]; then
                rm $ws_dir
            fi
            if [[ -d $ws_dir ]]; then
                if [[ -d $opt_dir && ! -L $opt_dir ]]; then
                    rm -rf ${opt_dir}
                fi
            else
                printf "Moving %s to %s\n" $opt_dir $ws_dir
                rsync -az $opt_dir $ws_dir
                rm -rf $opt_dir
            fi
            printf "Creating symlink from %s to %s\n" $ws_dir $opt_dir
            ln -s $ws_dir $opt_dir
        fi
    else 
        # Should be a symlink unless user has moved things - We can't handle that
        if [[ ! -e $ws_dir ]]; then
            printf "Creating symlink from %s to %s\n" $opt_dir $ws_dir
            ln -sf $opt_dir $ws_dir
        fi
    fi
done
}


function init_set_cf_tunnel_wanted() {
    if [[ -n $CF_TUNNEL_TOKEN ]]; then
        export SUPERVISOR_START_CLOUDFLARED=1 
    else
        export SUPERVISOR_START_CLOUDFLARED=0
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
        RCLONE_MOUNT_COUNT=$(rclone listremotes |wc -w)
        export RCLONE_MOUNT_COUNT
        if [[ $RCLONE_MOUNT_COUNT -eq 0 ]]; then
            no_remotes_warning="You have no configured rclone remotes to be mounted\n"
            printf "%b" "${no_remotes_warning}"
            touch "${no_remotes_warning_file}"
            printf "%b" "${no_remotes_warning}" > ${no_remotes_warning_file}
        fi
    fi
}

function init_cloud_context() {
    # Don't run tmux automatically on vast.ai
    if [[ -n $VAST_NO_TMUX ]]; then
        touch /root/.no_auto_tmux
    fi
    
    if env | grep 'VAST' > /dev/null 2>&1; then
        export CLOUD_PROVIDER="vast.ai"
    elif env | grep 'RUNPOD' > /dev/null 2>&1; then
       export CLOUD_PROVIDER="runpod.io"
    elif env | grep 'PAPERSPACE' > /dev/null 2>&1; then
       export CLOUD_PROVIDER="paperspace.com"
    fi
}

# Ensure the files logtail needs to display during init
function init_create_logfiles() {
    touch /var/log/supervisor/{debug.log,preflight.log,provisioning.log}
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
    
    if [[ -n $MAMBA_DEFAULT_ENV ]]; then
      printf "micromamba activate %s\n" $MAMBA_DEFAULT_ENV >> /root/.bashrc
    fi
    
    printf "cd %s\n" "$WORKSPACE" >> /root/.bashrc
}

function init_get_provisioning_script() {
    if [[ -n  $PROVISIONING_SCRIPT ]]; then
        file="/opt/ai-dock/bin/provisioning.sh"
        curl -L -o ${file} ${PROVISIONING_SCRIPT}
        if [[ "$?" -eq 0 ]]; then
            dos2unix ${file}
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
