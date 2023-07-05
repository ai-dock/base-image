#!/bin/bash

trap 'kill $(jobs -p)' EXIT

# Tail and print logs for all of our services
# Needed for 'docker logs' and ssh users

# Ensure the log files we need are present, then tail

for file in /var/log/supervisor/*.log; do 
    tail -F "$file" &
done

sleep infinity