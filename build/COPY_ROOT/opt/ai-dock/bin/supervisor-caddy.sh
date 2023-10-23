#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
    rm -f /opt/caddy/etc/Caddyfile >/dev/null 2>&1
}

function start() {
    if [[ ${SERVERLESS,,} = "true" ]]; then
        printf "Refusing to start Caddy service in serverless mode\n"
        exit 0
    fi
    
    # Give processes time to register their ports
    sleep 2
    port_files="/run/http_ports/*"
    
    mkdir -p /opt/caddy/etc/
    cp -f /opt/caddy/share/base_config /opt/caddy/etc/Caddyfile
    
    for service in $port_files; do
        listen_port=$(jq -r .listen_port ${service})
        proxy_port=$(jq -r .proxy_port ${service})
        proxy_secure=$(jq -r .proxy_secure ${service})
        if [[ ${WEB_ENABLE_AUTH,,} != 'false' && ${proxy_secure,,} != 'false' ]]; then
            fwauth_string="import fwauth"
        else fwauth_string=""
        fi
        
        cp /opt/caddy/share/service_config /tmp/caddy
        sed -i "s/!PROXY_PORT/${proxy_port}/g" /tmp/caddy
        sed -i "s/!FWAUTH/${fwauth_string}/g" /tmp/caddy
        sed -i "s/!LISTEN_PORT/${listen_port}/g" /tmp/caddy
        cat /tmp/caddy >> /opt/caddy/etc/Caddyfile
        printf "\n" >> /opt/caddy/etc/Caddyfile
    done
    
    caddy fmt --overwrite /opt/caddy/etc/Caddyfile
    caddy run --config /opt/caddy/etc/Caddyfile
}

start 2>&1