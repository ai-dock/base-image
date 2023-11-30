#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
}

function start() {
    printf "Starting storage monitor..\n"
    exec /opt/ai-dock/storage_monitor/bin/storage-monitor.sh
}

start 2>&1