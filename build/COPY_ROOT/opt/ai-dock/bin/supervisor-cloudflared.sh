#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
}

function start() {
    if [[ -z $CF_TUNNEL_TOKEN ]]; then
        printf "Skipping Cloudflare daemon: No token\n"
        # No error - Supervisor will not atempt restart
        sleep 2
        exit 0
    fi

    printf "Starting Cloudflare daemon...\n"

    cloudflared tunnel --metrics localhost:2999 run --token "${CF_TUNNEL_TOKEN}"
}

start 2>&1