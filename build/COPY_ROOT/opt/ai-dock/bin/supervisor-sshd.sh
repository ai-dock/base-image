#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(lsof -t -i:${SSH_PORT}) > /dev/null 2>&1 &
    wait -n
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
    if [[ ${SERVERLESS,,} = "true" ]]; then
        printf "Refusing to start SSH service in serverless mode\n"
        exec sleep 6
    fi
    
    # Support previous config
    if [[ ! -v SSH_PORT || -z $SSH_PORT ]]; then
        SSH_PORT=${SSH_PORT_LOCAL:-22}
    fi
    
    ak_file="/root/.ssh/authorized_keys"
    if [[ ! $(ssh-keygen -l -f $ak_file) ]]; then
        printf "Skipping SSH server: No public key\n" 1>&2
        # No error - Supervisor will not atempt restart
        exec sleep 6
    fi
    
    # Dynamically check users - we might have a mounted /etc/passwd
    if ! id -u sshd > /dev/null 2>&1; then
        groupadd -r sshd
        useradd -r -g sshd -s /usr/sbin/nologin sshd
    fi
    
    printf "Starting SSH server on port ${SSH_PORT}...\n"

    kill -9 $(lsof -t -i:$SSH_PORT) > /dev/null 2>&1 &
    wait -n
    
    /usr/bin/ssh-keygen -A
    /usr/sbin/sshd -D -p $SSH_PORT
}

start 2>&1