#!/bin/bash

trap cleanup EXIT

function cleanup {
    kill $(jobs -p) > /dev/null 2>&1
    if [[ -n $name ]]; then
        fusermount -az "$local_path" >/dev/null 2>&1
        umount "$local_path" >/dev/null 2>&1
        rm -rf "$cache_dir" >/dev/null 2>&1
    fi
}

function start() {
    # Determine if rclone mount will be possible
    # Repeat of entrypoint, in case of manual start attempt
    capsh --print | grep "Current:" | grep -q cap_sys_admin
    if [[ $? -ne 0 && ! -f /dev/fuse ]]; then
        # Not in container with sufficient privileges
        printf "Environment unsuitable for rclone mount...\n"
        printf "rclone remains available via CLI\n"
        exec sleep 10
    else
        # As array
        readarray -t REMOTES < <(rclone listremotes)
    fi
    
    if [ ${#REMOTES[@]} -eq 0 ]; then
        printf "No remotes configured for rclone\n"
        exec sleep 10
    fi
    
    if [[ -z $PROC_NUM ]]; then
        PROC_NUM=0
    fi
    
    remote=${REMOTES[$PROC_NUM]}
    name="${remote%:*}"
    local_path="${WORKSPACE}remote/$name"
    cache_dir="${WORKSPACE}remote/.cache/$name"
    # Try really, really hard to ensure not already mounted/fix transport not connected errors
    fusermount -uz "${local_path}" >/dev/null 2>&1
    umount "$local_path" >/dev/null 2>&1
    printf "Mounting remote '%s' at %s" "$remote" "${local_path}..."
    rm -rf "$cache_dir" >/dev/null 2>&1
    mkdir -p "$cache_dir"
    chown "$WORKSPACE_UID.$WORKSPACE_GID" "$cache_dir"
    mkdir -p "${local_path}"
    chown "$WORKSPACE_UID.$WORKSPACE_GID" "$local_path"
    
    exec rclone mount \
        --allow-non-empty \
        --allow-other \
        --uid "$WORKSPACE_UID" \
        --gid "$WORKSPACE_GID" \
        --cache-dir "$cache_dir" \
        --vfs-cache-mode full \
        "${remote}" \
        "${local_path}"
}

start 2>&1