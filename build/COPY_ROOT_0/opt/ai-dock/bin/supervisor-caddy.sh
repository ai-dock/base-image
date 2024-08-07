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

    # Upgrade http to https on the same port
    
    if [[ ${WEB_ENABLE_HTTPS,,} == true ]]; then
        cert_path="/opt/caddy/tls/container.crt"
        key_path="/opt/caddy/tls/container.key"
        max_retries=5
        # Avoid key generation race condition
        attempts=0
        while [[ $attempts -lt $max_retries ]]; do
            if [[ -f $(realpath $cert_path) && -f $(realpath $key_path) ]]; then
                if validate_cert_and_key; then
                    echo "Certificate and key are present and valid."
                    export CADDY_TLS_ELEVATION_STRING=$'http_redirect\ntls'
                    export CADDY_TLS_LISTEN_STRING="tls /opt/caddy/tls/container.crt /opt/caddy/tls/container.key"
                    break
                else
                    echo "Files are present but invalid, attempt $((attempts + 1)) of $MAX_RETRIES."
                fi
            else
                echo "Waiting for certificate and key to be present, attempt $((attempts + 1)) of $MAX_RETRIES."
            fi
            # Increment the retry counter
            attempts=$((attempts + 1))
            # Wait before retrying
            sleep 5
        done
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

function validate_cert_and_key() {
  if openssl x509 -in "$cert_path" -noout > /dev/null 2>&1 && \
     openssl rsa -in "$key_path" -check -noout > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

start 2>&1