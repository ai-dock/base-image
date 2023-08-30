#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

# Tail and print logs for all of our services
# Needed for 'docker logs' and ssh users

# Ensure the log files we need are present, then tail

for file in /var/log/supervisor/*.log; do 
    tail -F "$file" &
done

wait