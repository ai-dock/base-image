#!/bin/bash

trap init_cleanup EXIT

function init_cleanup() {
    printf "Cleaning up...\n"
    # Each running process should have its own cleanup routine
    supervisorctl stop all
    kill -9 $(</run/supervisord.pid) > /dev/null 2>&1
    rm -f /run/supervisor.sock
    rm -f /run/supervisord.pid
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
    printf "%s" "$!" > /run/supervisord.pid
    # Redirect output to files - Logtail will now handle
    init_sync_mamba_envs > /var/log/sync.log 2>&1
    init_sync_opt >> /var/log/sync.log 2>&1
    rm /run/workspace_sync
    init_source_preflight_scripts > /var/log/preflight.log 2>&1
    init_debug_print > /var/log/debug.log 2>&1
    init_get_provisioning_script > /var/log/provisioning.log 2>&1
    init_run_provisioning_script >> /var/log/provisioning.log 2>&1
    # Removal of this file will trigger fastapi placeholder shutdown and service start
    rm /run/container_config
    printf "Init complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
    # Don't exit unless supervisord is killed
    wait "$(</run/supervisord.pid)"
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
  init_source_preflight_scripts > /var/log/preflight.log 2>&1
  rm /run/container_config
  supervisord -c /etc/supervisor/supervisord.conf &
  printf "%s" "$!" > /run/supervisord.pid
  printf "Init complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
  wait "$(</run/supervisord.pid)"
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
        printf "\n%s\n" "$SSH_PUBKEY" > /root/.ssh/authorized_keys
    fi
    
    # Alt names for $SSH_PUBKEY
    # runpod.io
    if [[ -n $PUBLIC_KEY ]]; then
        printf "\n%s\n" "$PUBLIC_KEY" > /root/.ssh/authorized_keys
    fi
    
    # vast.ai
    if [[ -n $SSH_PUBLIC_KEY ]]; then
        printf "\n%s\n" "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    fi
}

init_set_web_credentials() {
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
      export WEB_PASSWORD="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)"
  fi
  
  export WEB_PASSWORD_B64="$(printf "%s:%s" "$WEB_USER" "$WEB_PASSWORD" | base64)"
  
  if [[ -z $WEB_TOKEN ]]; then
      # Not the same as password
      export WEB_TOKEN="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
  fi

  if [[ -n $DISPLAY && -z $COTURN_PASSWORD ]]; then
        export COTURN_PASSWORD="auto_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)"
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
    # no defined workspace - Keep users close to the install
    if [[ -z $WORKSPACE ]]; then
        export WORKSPACE="/opt/"
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

    if [[ $WORKSPACE != "/opt/" ]]; then
        mkdir -p "${WORKSPACE}"
        chown ${WORKSPACE_UID}.${WORKSPACE_GID} "${WORKSPACE}"
        chmod g+s "${WORKSPACE}"
    fi
    
    # Determine workspace mount status
    if mountpoint "$WORKSPACE" > /dev/null 2>&1 || [[ $WORKSPACE_MOUNTED == "force" ]]; then
        export WORKSPACE_MOUNTED=true
        mkdir -p "${WORKSPACE}"storage
    else
        export WORKSPACE_MOUNTED=false
        ln -sT /opt/storage "${WORKSPACE}"storage > /dev/null 2>&1
        no_mount_warning_file="${WORKSPACE}WARNING-NO-MOUNT.txt"
        no_mount_warning="$WORKSPACE is not a mounted volume.\n\nData saved here will not survive if the container is destroyed.\n\n"
        printf "%b" "${no_mount_warning}"
        touch "${no_mount_warning_file}"
        printf "%b" "${no_mount_warning}" > "${no_mount_warning_file}"
        if [[ $WORKSPACE != "/opt/" ]]; then
            printf "Find your software in /opt\n\n" >> "${no_mount_warning_file}"
        fi
    fi
    # Ensure we have a proper linux filesystem so we don't run into errors on sync
    if [[ $WORKSPACE_MOUNTED == "true" ]]; then
        test_file=${WORKSPACE}/.ai-dock-permissions-test
        touch $test_file
        if chown ${WORKSPACE_UID}.${WORKSPACE_GID} $test_file > /dev/null 2>&1; then
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
    if [[ ${WORKSPACE_MOUNTED,,} == "true" ]]; then
        home_dir=${WORKSPACE}home/${USER_NAME}
        mkdir -p $home_dir
        ln -s $home_dir /home/${USER_NAME}
    else
        home_dir=/home/${USER_NAME}
        mkdir -p ${home_dir}
    fi
    chown ${WORKSPACE_UID}.${WORKSPACE_GID} "$home_dir"
    chmod g+s "$home_dir"
    groupadd -g $WORKSPACE_GID $USER_NAME
    useradd -ms /bin/bash $USER_NAME -d $home_dir -u $WORKSPACE_UID -g $WORKSPACE_GID
    printf "user:%s" "${USER_PASSWORD}" | chpasswd
    usermod -a -G $USER_GROUPS $USER_NAME

    # For AMD devices - Ensure render group is created if /dev/kfd is present
    if ! getent group render >/dev/null 2>&1 && [ -e "/dev/kfd" ]; then
        groupadd -g "$(stat -c '%g' /dev/kfd)" render
        usermod -a -G render $USER_NAME
    fi

    # May not exist - todo check device ownership
    usermod -a -G sgx $USER_NAME
    # See the README (in)security notice
    printf "%s ALL=(ALL) NOPASSWD: ALL\n" ${USER_NAME} >> /etc/sudoers
    if [[ ! -e ${home_dir}/.bashrc ]]; then
        cp -f /root/.bashrc ${home_dir}
        cp -f /root/.profile ${home_dir}
        chown ${WORKSPACE_UID}:${WORKSPACE_GID} "${home_dir}/.bashrc" "${home_dir}/.profile"
    fi
    # Set initial keys to match root
    if [[ -e /root/.ssh/authorized_keys && ! -d ${home_dir}/.ssh ]]; then
        rm -f ${home_dir}/.ssh
        mkdir -pm 700 ${home_dir}/.ssh > /dev/null 2>&1
        cp -f /root/.ssh/authorized_keys ${home_dir}/.ssh/authorized_keys
        chown -R ${WORKSPACE_UID}:${WORKSPACE_GID} "${home_dir}/.ssh" > /dev/null 2>&1
        chmod 600 ${home_dir}/.ssh/authorized_keys > /dev/null 2>&1
        if [[ $WORKSPACE_MOUNTED == 'true' && $WORKSPACE_PERMISSIONS == 'false' ]]; then
            mkdir -pm 700 "/home/${USER_NAME}-linux"
            printf "StrictModes no\n" > /etc/ssh/sshd_config.d/no-strict.conf
        fi
    fi
    # Set username in startup sctipts
    sed -i "s/\$USER_NAME/$USER_NAME/g" /etc/supervisor/supervisord/conf.d/* 
}

function init_sync_mamba_envs() {
    # Support depreciated variable WORKSPACE_SYNC
    if [[ -n $WORKSPACE_SYNC ]]; then
        export WORKSPACE_MAMBA_SYNC="$WORKSPACE_SYNC"
    fi
    if [[ ${WORKSPACE_MOUNTED,,} == "true" && ${WORKSPACE_MAMBA_SYNC,,} == "true" ]]; then
        printf "Mamba sync start: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
        ws_mamba_target="${WORKSPACE}environments/${IMAGE_SLUG}"
        old_type_target="${WORKSPACE}environments/micromamba-${IMAGE_SLUG}"
        
        if [[ -f ${ws_mamba_target}/.move_complete ]]; then
            printf "Mamba environments already present at ${WORKSPACE}\n"

        elif [[ -f "${old_type_target}/.move_complete" ]]; then
            printf "Converting old sync format to improve compatibility...\n"
            # This shouldnt exist - A full copy would have been caught above
            rm -rf "${ws_mamba_target}"
            mkdir -p "${ws_mamba_target}"
            mv "${old_type_target}" "${ws_mamba_target}/micromamba"
            mv "${ws_mamba_target}/micromamba/.move_complete" "${ws_mamba_target}/.move_complete"

        else
            # Complete the copy if not serverless
            if [[ ${SERVERLESS,,} != 'true' ]]; then
                mkdir -p ${ws_mamba_target}
                printf "Moving mamba environments to %s...\n" "${WORKSPACE}"
                while sleep 10; do printf "Waiting for workspace mamba sync...\n"; done &
                    printf "Creating archive of /opt/micromamba...\n"
                    (cd /opt && tar -cf micromamba.tar micromamba --no-same-owner --no-same-permissions)
                    printf "Transferring mamba archive to %s...\n" "${ws_mamba_target}"
                    mv /opt/micromamba.tar "${ws_mamba_target}/micromamba.tar"
                    printf "Extracting mamba archive to %s...\n" "${ws_mamba_target}/micromamba/"
                    tar -xf "${ws_mamba_target}/micromamba.tar" -C "${ws_mamba_target}" --keep-newer-files --no-same-owner --no-same-permissions
                    rm -f "${ws_mamba_target}/micromamba.tar"
                # Kill the progress printer
                kill $!
                printf "Moved mamba environments to %s\n" "${WORKSPACE}"
                printf 1 > ${ws_mamba_target}/.move_complete
            else
                printf "Environments must be synchronised before enabling serverless mode\n..."
            fi
        fi

        if [[ -f "${ws_mamba_target}/.move_complete" ]]; then
            export MAMBA_ROOT_PREFIX="${ws_mamba_target}/micromamba"
            env-store MAMBA_ROOT_PREFIX
            rm -rf /opt/micromamba
            ln -s "${ws_mamba_target}/micromamba/" /opt/micromamba
            printf "Mamba sync complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
        else
            printf "Mamba sync failed: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
        fi
    fi
}

init_sync_opt() {
    # Applications at /opt *always* get synced to a mounted workspace
    if [[ $WORKSPACE_MOUNTED = "true" ]]; then
        printf "Opt sync start: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
        IFS=: read -r -d '' -a path_array < <(printf '%s:\0' "$OPT_SYNC")
        for item in "${path_array[@]}"; do
            opt_dir="/opt/${item}"
            if [[ ! -d $opt_dir || $opt_dir = "/opt/" || $opt_dir = "/opt/ai-dock" || $opt_dir = "/opt/micromamba" ]]; then
                continue
            fi
            
            ws_dir="${WORKSPACE}${item}"
            archive="${item}.tar"

            # remove old backup links (depreciated)
            rm -f "${ws_dir}-link"
            
            # Restarting stopped container
            if [[ -d $ws_dir && -L $opt_dir ]]; then
                printf "%s already symlinked to %s\n" $opt_dir $ws_dir
                continue
            fi
            
            # Reset symlinks first
            if [[ -L $opt_dir ]]; then rm -f "$opt_dir"; fi
            if [[ -L $ws_dir ]]; then rm -f "$ws_dir"; fi
            
            # Sanity check
            # User broke something - Container requires tear-down & restart
            if [[ ! -d $opt_dir && ! -d $ws_dir ]]; then
                printf "\U274C Critical directory ${opt_dir} is missing without a backup!\n"
                continue
            fi
            
            # Copy & delete directories
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

                    while sleep 10; do printf "Waiting for %s application sync...\n" "$item"; done &
                        printf "Creating archive of %s...\n" "$opt_dir"
                        (cd /opt && tar -cf "${archive}" "${item}" --no-same-owner --no-same-permissions)
                        printf "Transferring %s archive to %s...\n" "${item}" "${WORKSPACE}"
                        mv -f "/opt/${archive}" "${WORKSPACE}"
                        printf "Extracting %s archive to %s...\n" "${item}" "${WORKSPACE}${item}"
                        tar -xf "${WORKSPACE}${archive}" -C "${WORKSPACE}" --keep-newer-files --no-same-owner --no-same-permissions
                        rm -f "${WORKSPACE}${archive}"
                    # Kill the progress printer
                    kill $!
                    printf "Moved %s to %s\n" "$opt_dir" "$ws_dir"
                    printf 1 > $ws_dir/.move_complete
                fi
            fi
            
            # Create symlinks
            # Use workspace version
            if [[ -f "${ws_dir}/.move_complete" ]]; then
                printf "Creating symlink to %s at %s\n" $ws_dir $opt_dir
                rm -rf "$opt_dir"
                ln -s "$ws_dir" "$opt_dir"
            else
                printf "Expected to find %s but it's missing.  Using %s instead\n" "${ws_dir}/.move_complete" "$opt_dir"
            fi
        done
        printf "Opt sync complete: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
  fi
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

function init_source_preflight_scripts() {
    preflight_dir="/opt/ai-dock/bin/preflight.d"
    printf "Looking for scripts in %s...\n" "$preflight_dir"
    for script in /opt/ai-dock/bin/preflight.d/*.sh; do
        source "$script";
    done
}

function init_write_environment() {
    # Ensure all variables available for interactive sessions
    while IFS='=' read -r -d '' key val; do
        if [[  $key != "HOME" ]]; then
            env-store "$key"
        fi
    done < <(env -0)

    if [[ ! $(grep "# First init complete" /root/.bashrc) ]]; then
        printf "# First init complete\n" >> /root/.bashrc
        printf "umask 002\n" >> /root/.bashrc
        printf "source /opt/ai-dock/etc/environment.sh\n" >> /root/.bashrc

        if [[ -n $MAMBA_DEFAULT_ENV ]]; then
            printf "micromamba activate %s\n" $MAMBA_DEFAULT_ENV >> /root/.bashrc
        fi
        
        printf "cd %s\n" "$WORKSPACE" >> /root/.bashrc
        ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" | sudo tee /etc/timezone > /dev/null
    fi
}

function init_get_provisioning_script() {
    printf "Provisioning start: %s\n" "$(date +"%x %T.%3N")" >> /var/log/timing_data
    if [[ -n  $PROVISIONING_SCRIPT ]]; then
        file="/opt/ai-dock/bin/provisioning.sh"
        curl -L -o ${file} ${PROVISIONING_SCRIPT}
        if [[ "$?" -eq 0 ]]; then
            dos2unix "$file"
            sed -i "s/^#\!\/bin\/false$/#\!\/bin\/bash/" "$file"
            printf "Successfully created %s from %s\n" "$file" "$PROVISIONING_SCRIPT"
        else
            printf "Failed to fetch %s\n" "$PROVISIONING_SCRIPT"
            rm -f $file
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
            chown "${USER_NAME}":ai-dock "${file}"
            chmod 0755 "${file}"
            su -l "${USER_NAME}" -c "${file}"
            ldconfig
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

printf "Init started: %s\n" "$(date +"%x %T.%3N")" > /var/log/timing_data
umask 002
source /opt/ai-dock/etc/environment.sh
ldconfig
if [[ ${SERVERLESS,,} != 'true' ]]; then
    init_main "$@" exit
else
    init_serverless "$@"; exit
fi
