#!/bin/bash

trap cleanup EXIT

PORT=1122
METRICS_PORT=1022
SERVICE_NAME="Log Viewer"

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
    rm /run/http_ports/$PORT > /dev/null 2>&1
}

printf "{\"port\": \"$PORT\", \"metrics_port\": \"$METRICS_PORT\", \"service_name\": \"$SERVICE_NAME\"}" > /run/http_ports/$PORT


printf "Starting log service...\n"
logtail.sh -s &
micromamba -n fastapi run python /opt/ai-dock/fastapi/logviewer/main.py \
    -p $PORT \
    -r 1 \
    -t "Container Logs"
