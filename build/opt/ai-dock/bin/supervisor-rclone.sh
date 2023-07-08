#!/bin/bash

trap 'kill $(jobs -p)' EXIT

# As array
readarray -t REMOTES < <($MABMA_BASE_RUN rclone listremotes)

if [ ${#REMOTES[@]} -eq 0 ]; then
    printf "No remotes configured for rclone\n"
    exit 0
fi

if [[ -z $PROC_NUM ]]; then
    PROC_NUM=0
fi

remote=${REMOTES[$PROC_NUM]}
name="${remote%:*}"
local_path="/mnt/$name"
printf "Mounting remote '%s' at %s" "$remote" "${local_path}..." 
mkdir -p "/mnt/${remote%:*}"
umount "${local_path}" >/dev/null 2>&1
wait -n
$MABMA_BASE_RUN rclone mount "${remote}" "${local_path}"
