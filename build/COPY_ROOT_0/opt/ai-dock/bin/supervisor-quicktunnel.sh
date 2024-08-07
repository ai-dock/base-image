#!/bin/bash

trap cleanup EXIT

function cleanup() {
    fuser -k -SIGTERM ${metrics_port}/tcp > /dev/null 2>&1 &
    wait -n
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
    if [[ -z $PROC_NUM ]]; then
        # Something has gone awry, but no retry
        exec sleep 6
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
        if [[ ${WEB_ENABLE_HTTPS,,} == true && -f /opt/caddy/tls/container.crt && /opt/caddy/tls/container.key ]]; then
            tunnel="--no-tls-verify --url https://localhost:${proxy_port}"
        else
            tunnel="--url http://localhost:${proxy_port}"
        fi
        
        metrics="--metrics localhost:${metrics_port}"
    fi
    
    # Ensure the port is available (kill stale for restart)
    fuser -k -SIGKILL ${metrics_port}/tcp > /dev/null 2>&1 &
    wait -n
    
    cloudflared tunnel ${metrics} ${tunnel}
}

start 2>&1