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
    init_create_directories
    init_create_logfiles
    init_set_ssh_keys
    init_set_web_credentials
    init_direct_address
    init_set_workspace
    init_count_gpus
    init_count_quicktunnels
    init_count_rclone_remotes
    init_set_cf_tunnel_wanted
    touch /run/container_config
    touch /run/workspace_sync
    # Opportunity to process & manipulate config before supervisor
    init_source_config_script
    init_write_environment
    # Allow autostart processes to run early
    supervisord -c /etc/supervisor/supervisord.conf &
    # Redirect output to files - Logtail will now handle
    init_sync_mamba_envs > /var/log/sync.log 2>&1
    init_sync_opt >> /var/log/sync.log 2>&1
    init_set_workspace_permissions >> /var/log/sync.log 2>&1
    rm /run/workspace_sync
    init_source_preflight_script > /var/log/preflight.log 2>&1
    init_debug_print > /var/log/debug.log 2>&1
    init_get_provisioning_script > /var/log/provisioning.log 2>&1
    init_source_provisioning_script >> /var/log/provisioning.log 2>&1
    # Removal of this file will trigger fastapi shutdown and service start
    rm /run/container_config
    printf "Init complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
    # Don't exit unless supervisord is killed
    wait
}

# A trimmed down init suitable for serverless infrastructure
init_serverless() {
  init_set_envs "$@"
  touch "${WORKSPACE}.update_lock"
  export CF_QUICK_TUNNELS_COUNT=0
  export RCLONE_MOUNT_COUNT=0
  export SUPERVISOR_START_CLOUDFLARED=0
  init_direct_address
  init_set_workspace
  init_count_gpus
  init_create_directories
  init_create_logfiles
  touch /run/container_config
  touch /run/workspace_sync
  init_source_config_script
  init_write_environment
  init_sync_mamba_envs > /var/log/sync.log 2>&1
  init_sync_opt >> /var/log/sync.log 2>&1
  rm /run/workspace_sync
  init_source_preflight_script > /var/log/preflight.log 2>&1
  rm /run/container_config
  supervisord -c /etc/supervisor/supervisord.conf &
  printf "Init complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
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
      WEB_USER=user
  fi

  if [[ -z $WEB_PASSWORD && -z $WEB_PASSWORD_HASH ]]; then
      WEB_PASSWORD=password
  elif [[ -z $WEB_PASSWORD ]]; then
      WEB_PASSWORD="********"
  fi

  if [[ $WEB_PASSWORD != "********" ]]; then
      WEB_PASSWORD_HASH=$(hash-password.sh -p $WEB_PASSWORD -r 15)
      export WEB_PASSWORD="********"
  fi
  
  printf "%s %s" "$WEB_USER" "$WEB_PASSWORD_HASH" > /opt/caddy/etc/basicauth
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
    if [[ ! ${CF_QUICK_TUNNELS,,} = "true" ]]; then
        export CF_QUICK_TUNNELS_COUNT=0
    else
        export CF_QUICK_TUNNELS_COUNT=$(grep -l "METRICS_PORT" /opt/ai-dock/bin/supervisor-*.sh | wc -l)
    fi
}

function init_set_workspace() {
    if [[ -z $WORKSPACE ]]; then
        export WORKSPACE="/workspace/"
    else
        ws_tmp="/$WORKSPACE/"
        export WORKSPACE=${ws_tmp//\/\//\/}
    fi
    
    if [[ -f "${WORKSPACE}".update_lock ]]; then
        export AUTO_UPDATE=false
    fi

    mkdir -p "${WORKSPACE}"remote/.cache
    mkdir -p "${WORKSPACE}"storage
    
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
}

function init_sync_mamba_envs() {
    printf "Mamba sync start: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
    ws_mamba_target="${WORKSPACE}environments/micromamba-${IMAGE_SLUG}"
    if [[ -d ${WORKSPACE}/micromamba ]]; then
        mkdir -p ${WORKSPACE}/environments
        mv ${WORKSPACE}/micromamba "$ws_mamba_target"
    fi
    
    if [[ $WORKSPACE_MOUNTED = "false" ]]; then
      printf "No mount: Mamba environments remain in /opt\n"
    elif [[ ${WORKSPACE_SYNC,,} = "false" ]]; then
      printf "Skipping workspace sync: Mamba environments remain in /opt\n"
    elif [[ -f ${ws_mamba_target}/.move_complete ]]; then
      printf "Mamba environments already present at ${WORKSPACE}\n"
      rm -rf /opt/micromamba/*
      link-mamba-envs.sh
    else
      # Complete the copy if not serverless
      if [[ ${SERVERLESS,,} != 'true' ]]; then
          mkdir -p ${WORKSPACE}/environments
          printf "Moving mamba environments to %s...\n" "${WORKSPACE}"
          while sleep 10; do printf "Waiting for workspace mamba sync...\n"; done &
          rsync -auSHh --stats /opt/micromamba/ "${ws_mamba_target}"
          kill $!
          wait $! 2>/dev/null
          printf "Moved mamba environments to %s\n" "${WORKSPACE}"
          rm -rf /opt/micromamba/*
          printf 1 > ${ws_mamba_target}/.move_complete
          link-mamba-envs.sh
      fi
fi
printf "Mamba sync complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
}

init_sync_opt() {
  printf "Opt sync start: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
  IFS=: read -r -d '' -a path_array < <(printf '%s:\0' "$OPT_SYNC")
  for item in "${path_array[@]}"; do
    opt_dir="/opt/${item}"
    if [[ ! -d $opt_dir || $opt_dir = "/opt/"  ]]; then
        continue
    fi
    
    ws_dir=${WORKSPACE}/${item}
    ws_backup_link=${ws_dir}-link
    
    # Restarting stopped container
    if [[ -d $ws_dir && -L $opt_dir && ${WORKSPACE_SYNC,,} != "false" ]]; then
        printf "%s already symlinked to %s\n" $opt_dir $ws_dir
        continue
    fi
    
    # Reset symlinks first
    if [[ -L $opt_dir ]]; then rm "$opt_dir"; fi
    if [[ -L $ws_dir ]]; then rm "$ws_dir" "${ws_dir}-link"; fi
    
    # Sanity check
    # User broke something - Container requires tear-down & restart
    if [[ ! -d $opt_dir && ! -d $ws_dir ]]; then
        printf "\U274C Critical directory ${opt_dir} is missing without a backup!\n"
        continue
    fi
    
    # Copy & delete directories
    if [[ $WORKSPACE_MOUNTED = "true" && ${WORKSPACE_SYNC,,} != "false" ]]; then
        # Found a Successfully copied directory
        if [[ -d $ws_dir && -f $ws_dir/.move_complete ]]; then
            # Delete the container copy
            if [[ -d $opt_dir && ! -L $opt_dir ]]; then
                rm -rf "$opt_dir"
            fi
        # No/incomplete workspace copy
        else
            # Complete the copy if not serverless
            if [[ ${SERVERLESS,,} != 'true' ]]; then
                printf "Moving %s to %s\n" "$opt_dir" "$ws_dir"
                while sleep 10; do printf "Waiting for workspace application sync...\n"; done &
                rsync -auSHh --stats "$opt_dir" "$WORKSPACE"
                kill $!
                wait $! 2>/dev/null
                printf "Moved %s to %s\n" "$opt_dir" "$ws_dir"
                printf 1 > $ws_dir/.move_complete
                rm -rf "$opt_dir"
            fi
        fi
    fi
    
    # Create symlinks
    # Use container version over existing workspace version
    if [[ -d $opt_dir && -d $ws_dir ]]; then
        printf "Ignoring %s and creating symlink to %s at %s\n" $ws_dir $opt_dir $ws_backup_link
        ln -s "$opt_dir" "$ws_backup_link"
    # Use container version
    elif [[ -d $opt_dir ]]; then
        printf "Creating symlink to %s at %s\n" $opt_dir $ws_dir
        ln -s "$opt_dir" "$ws_dir"
    # Use workspace version
    elif [[ -d $ws_dir ]]; then
        printf "Creating symlink to %s at %s\n" $ws_dir $opt_dir
        ln -s "$ws_dir" "$opt_dir"
    fi
  done
  printf "Opt sync complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
}

init_set_workspace_permissions() {
    # Ensure the workspace owner can access files from outside of the container
    WORKSPACE_UID=$(stat -c '%u' "$WORKSPACE")
    export WORKSPACE_UID
    WORKSPACE_GID=$(stat -c '%g' "$WORKSPACE")
    export WORKSPACE_GID
    if [[ ${WORKSPACE_SYNC,,} != 'false' && ${SKIP_ACL,,} != 'false' && $WORKSPACE_UID -gt 0 ]]; then
        setfacl -R -d -m u:"${WORKSPACE_UID}":rwx "${WORKSPACE}"
        setfacl -R -d -m m:rwx "${WORKSPACE}"
        chown -R ${WORKSPACE_UID}.${WORKSPACE_GID} "${WORKSPACE}"
    fi
}

function init_set_cf_tunnel_wanted() {
    if [[ -n $CF_TUNNEL_TOKEN ]]; then
        export SUPERVISOR_START_CLOUDFLARED=1 
    else
        export SUPERVISOR_START_CLOUDFLARED=0
    fi
}

function init_count_rclone_remotes() {
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

function init_direct_address() {
    # Ensure set
    if [[ ! -v DIRECT_ADDRESS ]]; then
        DIRECT_ADDRESS=""
    fi
    
    if [[ ${DIRECT_ADDRESS,,} == "false" ]]; then
        export DIRECT_ADDRESS=""
    elif [[ -z $DIRECT_ADDRESS || ${DIRECT_ADDRESS_GET_WAN,,} == 'true' ]]; then
        if [[ ${DIRECT_ADDRESS_GET_WAN,,} == 'true' ]]; then
            export DIRECT_ADDRESS="$(curl https://icanhazip.com)"
        # Detected provider has direct connection method
        elif env | grep 'VAST' > /dev/null 2>&1; then
            export DIRECT_ADDRESS="auto#vast-ai"
            export CLOUD_PROVIDER="vast.ai"
        elif env | grep 'RUNPOD' > /dev/null 2>&1; then
           export DIRECT_ADDRESS="auto#runpod-io"
           export CLOUD_PROVIDER="runpod.io"
        # Detected provider does not support direct connections
        elif env | grep 'PAPERSPACE' > /dev/null 2>&1; then
            export DIRECT_ADDRESS=""
            export CLOUD_PROVIDER="paperspace.com"
        else
            export DIRECT_ADDRESS="localhost"
        fi
    fi
}

function init_create_directories() {
  mkdir -p /run/http_ports
  mkdir -p /opt/caddy/etc
}

# Ensure the files logtail needs to display during init
function init_create_logfiles() {
    touch /var/log/{logtail.log,config.log,debug.log,preflight.log,provisioning.log,sync.log}
}

function init_source_config_script() {
    # Child images can provide in their PATH
    printf "Looking for config.sh...\n"
    if [[ ! -f /opt/ai-dock/bin/config.sh ]]; then
        printf "Not found\n"
    else
        source /opt/ai-dock/bin/config.sh
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

function init_write_environment() {
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
    printf "Provisioning start: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
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
    if [[ ! -e "$WORKSPACE"/.update_lock ]]; then
        # Child images can provide in their PATH
        printf "Looking for provisioning.sh...\n"
        if [[ ! -f /opt/ai-dock/bin/provisioning.sh ]]; then
            printf "Not found\n"
        else
            source /opt/ai-dock/bin/provisioning.sh
        fi
    else
        printf "Refusing to provision container with %s.update_lock present\n" "$WORKSPACE"
    fi
    printf "Provisioning complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
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

printf "Init started: %s\n" "$(date +"%x %T.%3N")" > /var/log/timing_data
if [[ ${SERVERLESS,,} != 'true' ]]; then
    init_main "$@"; exit
else
    init_serverless "$@"; exit
fi
