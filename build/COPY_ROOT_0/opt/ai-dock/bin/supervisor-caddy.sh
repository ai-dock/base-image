#!/bin/bash

trap cleanup EXIT

function cleanup() {
    rm -f /opt/caddy/etc/Caddyfile >/dev/null 2>&1
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
    # Give processes time to register their ports
    sleep 2

    export SERVICEPORTAL_LOGIN=$(direct-url.sh -p "${SERVICEPORTAL_PORT_HOST:-1111}" -l "/login")
    env-store SERVICEPORTAL_LOGIN
    export SERVICEPORTAL_HOME=$(direct-url.sh -p "${SERVICEPORTAL_PORT_HOST:-1111}")
    env-store SERVICEPORTAL_HOME

    port_files="/run/http_ports/*"

    # Vast.ai certificates
    if [[ -f /etc/instance.crt && -f /etc/instance.key ]]; then
        cp /etc/instance.crt /opt/caddy/tls/container.crt
        cp /etc/instance.key /opt/caddy/tls/container.key
    fi

    # Upgrade http to https on the same port
    if [[ ${WEB_ENABLE_HTTPS,,} == true && -f /opt/caddy/tls/container.crt && /opt/caddy/tls/container.key ]]; then
        export CADDY_TLS_ELEVATION_STRING=$'http_redirect\ntls'
        export CADDY_TLS_LISTEN_STRING="tls /opt/caddy/tls/container.crt /opt/caddy/tls/container.key"
    fi
    
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