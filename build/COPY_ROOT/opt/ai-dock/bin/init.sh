#!/bin/bash

trap init_cleanup EXIT

function init_cleanup() {
    printf "Cleaning up...\n"
    # Each running process should have its own cleanup routine
    supervisorctl stop all
    kill -9 $(cat /var/run/supervisord.pid) > /dev/null 2>&1
    rm -f /var/run/supervisord.pid
    rm -f /var/run/supervisor.sock
}

function init_main() {
    init_set_envs "$@"
    init_create_directories
    init_create_logfiles
    init_set_ssh_keys
    init_direct_address
    init_set_web_credentials
    init_set_workspace
    init_count_gpus
    init_count_quicktunnels
    init_set_cf_tunnel_wanted
    touch /run/container_config
    touch /run/workspace_sync
    init_write_environment
    init_create_user
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
    init_run_provisioning_script >> /var/log/provisioning.log 2>&1
    # Removal of this file will trigger fastapi shutdown and service start
    rm /run/container_config
    printf "Init complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
    # Don't exit unless supervisord is killed
    wait
}

# A trimmed down init suitable for serverless infrastructure
init_serverless() {
  init_set_envs "$@"
  export CF_QUICK_TUNNELS_COUNT=0
  export SUPERVISOR_START_CLOUDFLARED=0
  init_set_workspace
  touch "${WORKSPACE}.update_lock"
  init_count_gpus
  init_create_directories
  init_create_logfiles
  touch /run/container_config
  touch /run/workspace_sync
  init_write_environment
  init_create_user
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
    
    # TODO: This does not handle cases where the tcp and udp port are both opened
    # Re-write envs; 
    ## 1) Strip quotes & replace ___ with a space
    ## 2) re-write cloud out-of-band ports
    while IFS='=' read -r -d '' key val; do
        if [[ $key == *"PORT_HOST" && $val -ge 70000 ]]; then
            declare -n vast_oob_tcp_port=VAST_TCP_PORT_${val}
            declare -n vast_oob_udp_port=VAST_UDP_PORT_${val}
            declare -n runpod_oob_tcp_port=RUNPOD_TCP_PORT_${val}
            if [[ -n $vast_oob_tcp_port ]]; then
                export $key=$vast_oob_tcp_port
            elif [[ -n $vast_oob_udp_port ]]; then
                export $key=$vast_oob_udp_port
            elif [[ -n $runpod_oob_tcp_port ]]; then
                export $key=$runpod_oob_tcp_port
            fi
        else
            export "${key}"="$(init_strip_quotes "${val//___/' '}")"
        fi
    done < <(env -0)
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
  export SERVICEPORTAL_LOGIN=$(direct-url.sh -p "${SERVICEPORTAL_PORT_HOST:-1111}" -l "/login")
  export SERVICEPORTAL_HOME=$(direct-url.sh -p "${SERVICEPORTAL_PORT_HOST:-1111}")

  # Handle cloud provider auto login
  # Vast.ai
  if [[ $(env | grep -i vast) && -n $OPEN_BUTTON_TOKEN ]]; then
      export WEB_TOKEN="${OPEN_BUTTON_TOKEN}"
      if [[ $WEB_PASSWORD == "password" ]]; then
          unset WEB_PASSWORD
      fi
  fi
  
  if [[ -z $WEB_USER ]]; then
      export WEB_USER=user
  fi

  if [[ -z $WEB_PASSWORD ]]; then
      export WEB_PASSWORD="$(openssl rand -base64 12)"
  fi
  
  export WEB_PASSWORD_B64="$(printf "%s:%s" "$WEB_USER" "$WEB_PASSWORD" | base64)"
  
  if [[ -z $WEB_TOKEN ]]; then
      # Not the same as password (probably!)
      export WEB_TOKEN="$(openssl rand -base64 32)"
  fi

  if [[ -n $DISPLAY && -z $COTURN_PASSWORD ]]; then
        export COTURN_PASSWORD="auto_$(openssl rand -base64 8)"
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
    if [[ ${CF_QUICK_TUNNELS,,} == "false" ]]; then
        export CF_QUICK_TUNNELS_COUNT=0
    else
        export CF_QUICK_TUNNELS_COUNT=$(grep -l "QUICKTUNNELS=true" /opt/ai-dock/bin/supervisor-*.sh | wc -l)
        if [[ -z $TUNNEL_TRANSPORT_PROTOCOL ]]; then
            export TUNNEL_TRANSPORT_PROTOCOL=http2
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
    
    WORKSPACE_UID=$(stat -c '%u' "$WORKSPACE")
    if [[ $WORKSPACE_UID -eq 0 ]]; then
        WORKSPACE_UID=1000
    fi
    export WORKSPACE_UID
    WORKSPACE_GID=$(stat -c '%g' "$WORKSPACE")
    if [[ $WORKSPACE_GID -eq 0 ]]; then
        WORKSPACE_GID=1000
    fi
    export WORKSPACE_GID
    
    if [[ -f "${WORKSPACE}".update_lock ]]; then
        export AUTO_UPDATE=false
    fi

    mkdir "${WORKSPACE}"
    chown ${WORKSPACE_UID}.${WORKSPACE_GID} "${WORKSPACE}"
    chmod g+s "${WORKSPACE}"
    mkdir "${WORKSPACE}"storage
    
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
    # Ensure we have a proper linux filesystem so we don't run into errors on sync
    if [[ $WORKSPACE_MOUNTED == "true" ]]; then
        test_file=${WORKSPACE}/.ai-dock-permissions-test
        touch $test_file
        if chown ${WORKSPACE_UID}.${WORKSPACE_GID} $test_file; then
            export WORKSPACE_PERMISSIONS=true
        else 
            export WORKSPACE_PERMISSIONS=false
        fi
        rm $test_file
    fi
}

# This is a convenience for X11 containers and bind mounts - No additional security implied.
# These are interactive containers; root will always be available. Secure your daemon.
function init_create_user() {
    home_dir=${WORKSPACE}home/${USER_NAME}
    mkdir -p ${home_dir}
    chown ${WORKSPACE_UID}.${WORKSPACE_GID} "$home_dir"
    chmod g+s "$home_dir"
    groupadd -g $WORKSPACE_GID $USER_NAME
    useradd -ms /bin/bash $USER_NAME -d $home_dir -u $WORKSPACE_UID -g $WORKSPACE_GID
    printf "user:%s" "${USER_PASSWORD}" | chpasswd
    usermod -a -G $USER_GROUPS $USER_NAME
    # May not exist - todo check device ownership
    usermod -a -G render $USER_NAME
    usermod -a -G sgx $USER_NAME
    ln -s $home_dir /home/${USER_NAME}
    # See the README (in)security notice
    printf "%s ALL=(ALL) NOPASSWD: ALL\n" ${USER_NAME} >> /etc/sudoers
    if [[ ! -e ${home_dir}/.bashrc ]]; then
        cp -f /root/.bashrc ${home_dir}
        chown ${WORKSPACE_UID}:${WORKSPACE_GID} "${home_dir}/.bashrc"
    fi
    # Set initial keys to match root
    if [[ -e /root/.ssh/authorized_keys  && ! -d ${home_dir}/.ssh ]]; then
        mkdir -pm 700 ${home_dir}/.ssh
        cp /root/.ssh/authorized_keys ${home_dir}/.ssh
        chown -R ${WORKSPACE_UID}:${WORKSPACE_GID} "${home_dir}/.ssh"
        chmod 600 ${home_dir}/.ssh/authorized_keys
        if [[ $WORKSPACE_MOUNTED == 'true' && $WORKSPACE_PERMISSIONS == 'false' ]]; then
            mkdir -pm 700 "/home/${USER_NAME}-linux"
            mv "${home_dir}/.ssh" "/home/${USER_NAME}-linux/.ssh"
            chown -R ${WORKSPACE_UID}.${WORKSPACE_GID} "/home/${USER_NAME}-linux"
            chmod 600 "/home/${USER_NAME}-linux/.ssh/authorized_keys"
            ln -s "/home/${USER_NAME}-linux/.ssh" "${home_dir}/.ssh"
        fi
    fi
    # Set username in startup sctipts
    sed -i "s/\$USER_NAME/$USER_NAME/g" /etc/supervisor/supervisord/conf.d/* 
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
    elif [[ ${WORKSPACE_SYNC,,} != "true" ]]; then
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
            rsync -rlptDu --stats /opt/micromamba/ "${ws_mamba_target}"
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
    if [[ -d $ws_dir && -L $opt_dir && ${WORKSPACE_SYNC,,} == "true" ]]; then
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
    if [[ $WORKSPACE_MOUNTED = "true" && ${WORKSPACE_SYNC,,} == "true" ]]; then
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
    # Ensure the workspace owner/container user can access files from outside of the container
    /opt/ai-dock/bin/fix-permissions.sh
}

function init_set_cf_tunnel_wanted() {
    if [[ -n $CF_TUNNEL_TOKEN ]]; then
        export SUPERVISOR_START_CLOUDFLARED=1 
    else
        export SUPERVISOR_START_CLOUDFLARED=0
    fi
}

function init_direct_address() {
    export EXTERNAL_IP_ADDRESS="$(dig +short myip.opendns.com @resolver1.opendns.com)"
    if [[ -z $EXTERNAL_IP_ADDRESS ]];then
        export EXTERNAL_IP_ADDRESS=$(curl -s ifconfig.me)
    fi
    if [[ ! -v DIRECT_ADDRESS ]]; then
        DIRECT_ADDRESS=""
    fi
    
    if [[ ${DIRECT_ADDRESS,,} == "false" ]]; then
        export DIRECT_ADDRESS=""
    elif [[ -z $DIRECT_ADDRESS || ${DIRECT_ADDRESS_GET_WAN,,} == 'true' ]]; then
        if [[ ${DIRECT_ADDRESS_GET_WAN,,} == 'true' ]]; then
            export DIRECT_ADDRESS="$EXTERNAL_IP_ADDRESS"
        # Detected provider has direct connection method
        elif env | grep 'VAST' > /dev/null 2>&1; then
            export DIRECT_ADDRESS="auto#vast-ai"
            export CLOUD_PROVIDER="vast.ai"
            export EXTERNAL_IP_ADDRESS=${PUBLIC_IPADDR}
        elif env | grep 'RUNPOD' > /dev/null 2>&1; then
           export DIRECT_ADDRESS="auto#runpod-io"
           export CLOUD_PROVIDER="runpod.io"
           export EXTERNAL_IP_ADDRESS=${RUNPOD_PUBLIC_IP}
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
  mkdir -m 2770 -p /run/http_ports
  chown root.ai-dock /run/http_ports
  mkdir -p /opt/caddy/etc
}

# Ensure the files logtail needs to display during init
function init_create_logfiles() {
    touch /var/log/{logtail.log,config.log,debug.log,preflight.log,provisioning.log,sync.log}
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
    while IFS='=' read -r -d '' key val; do
        if [[  $key != "HOME" ]]; then
            env-store "$key"
        fi
    done < <(env -0)

    # g=rw permissions on new files owned by root
    printf "umask 002\n" >> /root/.bashrc

    if [[ -n $MAMBA_DEFAULT_ENV ]]; then
      printf "micromamba activate %s\n" $MAMBA_DEFAULT_ENV >> /root/.bashrc
    fi
    
    printf "cd %s\n" "$WORKSPACE" >> /root/.bashrc
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" | sudo tee /etc/timezone > /dev/null
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

function init_run_provisioning_script() {
    if [[ ! -e "$WORKSPACE"/.update_lock ]]; then
        file="/opt/ai-dock/bin/provisioning.sh"
        printf "Looking for provisioning.sh...\n"
        if [[ ! -f ${file} ]]; then
            printf "Not found\n"
        else
            chown ${USER_NAME}:ai-dock ${file}
            chmod 0755 ${file}
            su ${USER_NAME} -c ${file}
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
        printf "/opt/ai-dock/etc/environment.sh...\n\n"
        cat /opt/ai-dock/etc/environment.sh
        printf "\n--------------------------------------------\n"
        printf ".bashrc...\n\n"
        cat /root/.bashrc
        printf "\n---------- END DEBUG INFO---------- \n\n\n"
    fi
}

umask 002
printf "Init started: %s\n" "$(date +"%x %T.%3N")" > /var/log/timing_data
if [[ ${SERVERLESS,,} != 'true' ]]; then
    init_main "$@"; exit
else
    init_serverless "$@"; exit
fi
