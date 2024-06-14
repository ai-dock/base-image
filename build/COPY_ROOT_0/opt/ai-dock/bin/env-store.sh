#!/bin/bash

# Store environment variables so they can be used by supervisor processes
key="$1"
value="$(printenv $1)"
code=$?

if [[ -z $key ]]; then
    printf "Usage: env-store key\n"
    exit 1
fi

if [[ $code -ne 0 ]]; then
    printf "Could not store key: %s\n" "$key"
    exit 1
fi

printf "export %s=\'%s\'\n" "${key}" "${value}" >> /opt/ai-dock/etc/environment.sh
printf "Stored environment variable '%s': %s\n" "$key" "$value"