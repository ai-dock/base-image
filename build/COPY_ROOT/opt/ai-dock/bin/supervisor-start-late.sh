#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

# We need to start some processes after provisioning...
# They should be marked autostart=false

printf "Restarting logtail service to detect late-starting process logs...\n"
micromamba run -n system supervisorctl -c /etc/supervisor/supervisord.conf start all
# Pick up new log files
micromamba run -n system supervisorctl -c /etc/supervisor/supervisord.conf restart logtail
