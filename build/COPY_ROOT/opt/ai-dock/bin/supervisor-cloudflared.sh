#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
}

if [[ -z $CF_TUNNEL_TOKEN ]]; then
    printf "Skipping Cloudflare daemon: No token\n"
    # No error - Supervisor will not atempt restart
    sleep 3
    exit 0
fi


printf "Starting Cloudflare daemon...\n"

cloudflared tunnel run --token "${CF_TUNNEL_TOKEN}"