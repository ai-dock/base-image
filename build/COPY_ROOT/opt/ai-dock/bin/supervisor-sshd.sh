#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
}

if [[ -z $SSH_PORT ]]; then
    SSH_PORT=22
fi

ak_file="/root/.ssh/authorized_keys"
if [[ ! $(ssh-keygen -l -f $ak_file) ]]; then
    printf "Skipping SSH server: No public key\n" 1>&2
    # No error - Supervisor will not atempt restart
    sleep 3
    exit 0
fi

# Dynamically check users - we might have a mounted /etc/passwd
if ! id -u sshd > /dev/null 2>&1; then
    groupadd -r sshd
    useradd -r -g sshd -s /usr/sbin/nologin sshd
fi

printf "Starting SSH server...\n"
micromamba -n ${MAMBA_BASE_ENV} run /opt/micromamba/envs/"${MAMBA_BASE_ENV}"/bin/ssh-keygen -A

micromamba -n ${MAMBA_BASE_ENV} run /opt/micromamba/envs/"${MAMBA_BASE_ENV}"/bin/sshd -D -p $SSH_PORT