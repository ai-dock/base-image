#!/bin/bash

trap cleanup EXIT

function cleanup {
    kill $(jobs -p)
    if [[ ! -z $name ]]; then
        fusermount -az $local_path >/dev/null 2>&1
        umount $local_path >/dev/null 2>&1
        rm -rf $cache_dir >/dev/null 2>&1
    fi
}

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
local_path="/workspace/remote/$name"
cache_dir="/workspace/remote/.cache/$name"
# Try really, really hard to ensure not already mounted/fix transport not connected errors
fusermount -uz "${local_path}" >/dev/null 2>&1
umount "$local_path" >/dev/null 2>&1
printf "Mounting remote '%s' at %s" "$remote" "${local_path}..."
rm -rf "$cache_dir" >/dev/null 2>&1
mkdir -p "$cache_dir"
chown "$WORKSPACE_UID.$WORKSPACE_GID" $cache_dir
mkdir -p "${local_path}"
chown "$WORKSPACE_UID.$WORKSPACE_GID" $local_path
wait -n
$MABMA_BASE_RUN rclone mount \
    --allow-non-empty \
    --allow-other \
    --uid $WORKSPACE_UID \
    --gid $WORKSPACE_GID \
    --cache-dir "$cache_dir" \
    --vfs-cache-mode full \
    "${remote}" \
    "${local_path}"
    