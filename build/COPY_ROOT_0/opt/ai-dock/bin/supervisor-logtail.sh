#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
    printf "Starting logtail service...\n"
    sleep 2
    logtail.sh -s
}

start 2>&1