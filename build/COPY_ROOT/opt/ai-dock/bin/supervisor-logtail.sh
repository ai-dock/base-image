#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) > /dev/null 2>&1
}

function start() {
    printf "Starting logtail service...\n"
    sleep 2
    exec logtail.sh -s
}

start 2>&1