#!/bin/bash

trap cleanup EXIT

METRICS_PORT=2999

function cleanup() {
    kill $(lsof -t -i:${METRICS_PORT}) > /dev/null 2>&1 &
    wait -n
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
    if [[ -z $CF_TUNNEL_TOKEN ]]; then
        printf "Skipping Cloudflare daemon: No token\n"
        # No error - Supervisor will not atempt restart
        exec sleep 5
    fi

    printf "Starting Cloudflare daemon...\n"

    kill -9 $(lsof -t -i:${METRICS_PORT}) > /dev/null 2>&1 &
    wait -n

    cloudflared tunnel --metrics localhost:"${METRICS_PORT}" run --token "${CF_TUNNEL_TOKEN}"
}

start 2>&1