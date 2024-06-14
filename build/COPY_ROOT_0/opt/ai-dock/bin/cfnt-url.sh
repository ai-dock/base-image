#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

unset -v port
unset -v location

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

listen_port=2999
ingress_json="$(curl -s http://localhost:${listen_port}/config | jq -r .config.ingress 2>/dev/null)"
ingress_count="$(printf "%s" "$ingress_json" | jq length 2>/dev/null)"

for ((i=0;i<ingress_count;i++)); do
    ingress="$(printf "%s" "$ingress_json" | jq -r ".[${i}]" 2>/dev/null)"
    service_port="$(printf "%s" "$ingress" | jq -r .service | cut -d ":" -f 3 2>/dev/null)"
    
    if [[ $service_port == "$port" ]]; then
        printf "https://%s%s\n" "$(printf "%s" "$ingress" | jq -r .hostname 2>/dev/null)" "$location"
        exit 0
    fi
done

printf "No cloudflare tunnel running for localhost:%s\n" $port
exit 1
