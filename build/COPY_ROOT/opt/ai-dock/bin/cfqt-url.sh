#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

unset -v port
metrics=""
while getopts p: flag
do
    case "${flag}" in
        p) port="${OPTARG}";;
    esac
done

if [[ -z $port ]]; then
    printf "port (-p) is required\n"
    exit 1
fi



if mport=$(jq -r .metrics_port /run/http_ports/$port 2>/dev/null) && cf_host=$(curl -s http://localhost:${mport}/quicktunnel | jq -r .hostname 2>/dev/null); then
    printf "https://%s\n" $cf_host
    exit 0
else
    printf "No cloudflare quicktunnel running for localhost:%s\n" $port
    exit 1
fi