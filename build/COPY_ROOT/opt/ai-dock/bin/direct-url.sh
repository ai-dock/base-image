#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

unset -v port
unset -v url

metrics=""
while getopts l:p: flag
do
    case "${flag}" in
        l) location="${OPTARG}";;
        p) port="${OPTARG}";;
    esac
done

if [[ -z $port ]]; then
    printf "port (-p) is required\n"
    exit 1
fi

function get_url {
    # Vast.ai
    if [[ $DIRECT_ADDRESS == "auto#vast-ai" ]]; then
        declare -n vast_mapped_port=VAST_TCP_PORT_${port}
        if [[ -n $vast_mapped_port && -n $PUBLIC_IPADDR ]]; then
            url="http://${PUBLIC_IPADDR}:${vast_mapped_port}"
        fi
    # Runpod.io
    elif [[ $DIRECT_ADDRESS == "auto#runpod-io" ]]; then
        declare -n runpod_mapped_port=RUNPOD_TCP_PORT_${port}
        if [[ -n $runpod_mapped_port && -n $RUNPOD_PUBLIC_IP ]]; then
            url="http://${RUNPOD_PUBLIC_IP}:${runpod_mapped_port}"
        elif [[ -n $RUNPOD_POD_ID ]]; then
            url="https://${RUNPOD_POD_ID}-${port}.proxy.runpod.net"
        fi
    # Other cloud / local
    else
        url="http://${DIRECT_ADDRESS}:${port}"
    fi
    
    if [[ -n $url ]]; then
        printf "%s%s\n" "$url" "$location"
        exit 0
    else
        printf "Could not create URL\n"
        exit 1
    fi
}

get_url