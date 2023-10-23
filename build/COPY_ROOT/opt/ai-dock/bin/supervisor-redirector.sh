#!/bin/bash

trap cleanup EXIT

LISTEN_PORT=11111
METRICS_PORT=21111
PROXY_PORT=1111
PROXY_SECURE=false
SERVICE_NAME="Port Redirector"

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
    rm /run/http_ports/$PROXY_PORT > /dev/null 2>&1
}

function start() {
    if [[ ${SERVERLESS,,} = "true" ]]; then
        printf "Refusing to start $SERVICE_NAME service in serverless mode\n"
        exit 0
    fi
    
    file_content="$(
      jq --null-input \
        --arg listen_port "${LISTEN_PORT}" \
        --arg metrics_port "${METRICS_PORT}" \
        --arg proxy_port "${PROXY_PORT}" \
        --arg proxy_secure "${PROXY_SECURE,,}" \
        --arg service_name "${SERVICE_NAME}" \
        '$ARGS.named'
    )"
    
    printf "%s\n" "$file_content" > /run/http_ports/$PROXY_PORT
    
    printf "Starting redirector server...\n"
    kill -9 $(lsof -t -i:$LISTEN_PORT) > /dev/null 2>&1 &
    wait -n
    /usr/bin/python3 /opt/ai-dock/fastapi/redirector/main.py \
        -p $LISTEN_PORT
}

start 2>&1