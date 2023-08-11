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
    exit 0
fi

printf "Starting SSH server...\n"

wait -n
/usr/sbin/sshd -D -p $SSH_PORT