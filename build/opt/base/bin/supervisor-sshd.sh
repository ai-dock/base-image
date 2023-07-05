#!/bin/bash

trap 'kill $(jobs -p)' EXIT

AU_FILE="/root/.ssh/authorized_keys"
ssh-keygen -l -f $AU_FILE

if [[ $? -gt 0 ]]; then
    printf "Skipping SSH server: No public key\n" 1>&2
    exit 0
fi

printf "Starting SSH server...\n"

wait -n
/usr/sbin/sshd -D