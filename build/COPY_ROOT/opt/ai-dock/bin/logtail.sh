#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

while getopts s flag
do
    case "${flag}" in
        s) sys_mode="true";;
    esac
done

# Tail and print logs for all of our services
# Needed for 'docker logs' and ssh users

if [[ $sys_mode = "true" ]]; then
    printf "Gathering logs..."
    # Give processes time to create their logs before start
    sleep 1
    tail -fn512 /var/log/config.log \
                /var/log/sync.log \
                /var/log/sync_*.log \
                /var/log/preflight.log \
                /var/log/debug.log \
                /var/log/provisioning.log \
                /var/log/supervisor/*.log | tee -a /var/log/logtail.log
else
    tail -fn512 /var/log/logtail.log
fi

wait