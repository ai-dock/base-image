#!/bin/bash

trap cleanup EXIT

function cleanup() {
    rm -f /opt/caddy/etc/Caddyfile >/dev/null 2>&1
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
    if [[ ${SERVERLESS,,} = "true" ]]; then
        printf "Refusing to start Caddy service in serverless mode\n"
        exec sleep 5
    fi
    
    # Give processes time to register their ports
    sleep 2
    port_files="/run/http_ports/*"
    
    cp -f /opt/caddy/share/base_config /opt/caddy/etc/Caddyfile
    
    for service in $port_files; do
        listen_port=$(jq -r .listen_port ${service})
        proxy_port=$(jq -r .proxy_port ${service})
        proxy_secure=$(jq -r .proxy_secure ${service})
        
        if [[ -f /opt/caddy/share/service_config_${listen_port} ]]; then
            template_file="/opt/caddy/share/service_config_${listen_port}"
        else
            template_file="/opt/caddy/share/service_config"
        fi

        cp "${template_file}" /tmp/caddy
        sed -i "s/!PROXY_PORT/${proxy_port}/g" /tmp/caddy
        sed -i "s/!LISTEN_PORT/${listen_port}/g" /tmp/caddy
        cat /tmp/caddy >> /opt/caddy/etc/Caddyfile
        printf "\n" >> /opt/caddy/etc/Caddyfile
    done
    
    caddy fmt --overwrite /opt/caddy/etc/Caddyfile
    caddy run --config /opt/caddy/etc/Caddyfile
}

start 2>&1