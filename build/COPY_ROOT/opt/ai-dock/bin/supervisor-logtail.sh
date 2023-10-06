#!/bin/bash

trap cleanup EXIT

LISTEN_PORT=1822
METRICS_PORT=1922
PROXY_PORT=1122
PROXY_SECURE=true
SERVICE_NAME="Log Viewer"

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
    rm /run/http_ports/$PORT > /dev/null 2>&1
}

file_content=$(
  jq --null-input \
    --arg listen_port "${LISTEN_PORT}" \
    --arg metrics_port "${METRICS_PORT}" \
    --arg proxy_port "${PROXY_PORT}" \
    --arg proxy_secure "${PROXY_SECURE,,}" \
    --arg service_name "${SERVICE_NAME}" \
    '$ARGS.named'
)

printf "%s" $file_content > /run/http_ports/$PROXY_PORT

printf "Starting log service...\n"
logtail.sh -s &
/usr/bin/python3 /opt/ai-dock/fastapi/logviewer/main.py \
    -p $LISTEN_PORT \
    -r 0 \
    -t "Container Logs"
