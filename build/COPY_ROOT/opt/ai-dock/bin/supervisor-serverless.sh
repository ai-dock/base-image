#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
}

function start() {
    if [[ ${SERVERLESS,,} != true ]]; then
        printf "Refusing to start serverless worker without \$SERVERLESS=true"
        exit 0
    fi
    
    # Delay launch until workspace is ready
    # This should never happen - Don't sync on serverless!
    if [[ -f /run/workspace_moving || -f /run/provisioning_script ]]; then
        while [[ -f /run/workspace_moving || -f /run/provisioning_script ]]; do
            sleep 1
        done
    fi
    
    printf "Starting %s serverless worker...\n" ${CLOUD_PROVIDER}
    
    if [[ ${CLOUD_PROVIDER} = "runpod.io" ]]; then
        micromamba -n runpod run \
            python -u /opt/ai-dock/serverless/providers/runpod/worker.py
    else
        printf "No serverless worker available in this environment"
    fi
}

start 2>&1