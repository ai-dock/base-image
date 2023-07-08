#!/bin/bash

# Script to help overcome difficulties setting envs at vast.ai
# Allows passing environment vars through entrypoint args

# docker run ... supervisord-env.sh SOME_VAR="some value"...
# Also allows killing the container from inside.


trap 'kill $(jobs -p)' EXIT


for i in "$@"; do
    IFS=\= read -r key val <<< "$i"
    if [[ ! -z $key && ! -z $val ]]; then
        export "${key}"="${val}"
        printf "export %s=\"%s\"\n" "$key" "$val" >> /root/.bashrc
    fi
done

# Child images can provide in their PATH
printf "Looking for preflight.sh...\n"
which preflight.sh
if [[ $? -ne 0  ]]; then
    printf "Not found\n"
else
    preflight.sh
fi

# Killing supervisord will stop/force restart the container
wait -n
$MAMBA_BASE_RUN supervisord -c /etc/supervisor/supervisord.conf