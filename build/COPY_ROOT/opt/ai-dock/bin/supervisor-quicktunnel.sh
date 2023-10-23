#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

function start() {
    if [[ -z $PROC_NUM ]]; then
        # Something has gone awry, but no retry
        exit 0
    fi
    
    # Give processes time to register their ports
    sleep 2
    port_files=(/run/http_ports/*)
    proxy_port=$(jq -r .proxy_port ${port_files[$PROC_NUM]})
    metrics_port=$(jq -r .metrics_port ${port_files[$PROC_NUM]})
    
    if [[ -z $proxy_port || -z $metrics_port ]]; then
        printf "port not configured\n"
        exit 1
    else
        # Tunnel the proxy port so we get authentication
        tunnel="--url localhost:${proxy_port}"
        metrics="--metrics localhost:${metrics_port}"
    fi
    
    cloudflared tunnel ${metrics} ${tunnel}
}

start 2>&1