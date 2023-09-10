#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
    rm /run/http_ports/$PORT > /dev/null 2>&1
}

PORT=1111
METRICS_PORT=1011
SERVICE_NAME="Port Redirector"
printf "{\"port\": \"$PORT\", \"metrics_port\": \"$METRICS_PORT\", \"service_name\": \"$SERVICE_NAME\"}" > /run/http_ports/$PORT


printf "Starting redirector server...\n"
micromamba -n fastapi run python /opt/ai-dock/fastapi/redirector/main.py
