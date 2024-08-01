#!/bin/bash

trap cleanup EXIT

function cleanup() {
    fuser -k -SIGTERM 22/tcp > /dev/null 2>&1 &
    wait -n
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
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

    fuser -k -SIGKILL 22/tcp > /dev/null 2>&1 &
    wait -n
    
    /usr/bin/ssh-keygen -A
    /usr/sbin/sshd -D -p 22
}

start 2>&1