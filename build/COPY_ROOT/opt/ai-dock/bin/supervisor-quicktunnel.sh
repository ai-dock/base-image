#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

if [[ -z $PROC_NUM ]]; then
    # Something has gone awry, but no retry
    exit 0
fi

# Give processes time to register their ports
sleep 3
port_files=(/run/http_ports/*)
port=${port_files[$PROC_NUM]##*/}
mport=$(jq -r .metrics_port ${port_files[$PROC_NUM]})


if [[ -z $port || -z $mport ]]; then
    printf "port not configured\n"
    exit 1
else
    tunnel="--url localhost:${port}"
    metrics="--metrics localhost:${mport}"
fi

cloudflared tunnel ${metrics} ${tunnel}