#!/bin/bash

if [[ ! $(grep "# First init complete" ~/.bashrc) || -f /run/workspace_sync || -f /run/container_config ]]; then
    printf "\e[91m*** Container is not ready ***\e[0m\n"

    if [[ ! $(grep "# First init complete" ~/.bashrc) ]]; then
        printf "\e[91m>>>\e[0m You have logged in before the init process has completed.\n"
    fi

    if [[ -f /var/run/workspace_sync ]]; then
        printf "\e[91m>>>\e[0m Workspace sync is not yet complete.\n\e[91m>>>\e[0m Changes may not be saved (see /var/log/sync.log)\n"
    fi

    if [[ -f /var/run/container_config ]]; then
        printf "\e[91m>>>\e[0m Container provisioning is not yet complete.\n\e[91m>>>\e[0m Requested software may not be available (see /var/log/provisioning.log)\n\n"
    fi

    printf "You can track the progress of container startup by typing 'logtail'\n\n"
fi