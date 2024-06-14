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

mport=$(jq -r .metrics_port /run/http_ports/$port 2>/dev/null)
if [[ -n $mport ]]; then
    cf_host=$(curl -s http://localhost:${mport}/quicktunnel | jq -r .hostname 2>/dev/null)
fi

if [[ -n $mport && -n $cf_host ]]; then
    printf "https://%s%s\n" "$cf_host" "$location"
    exit 0
else
    printf "No cloudflare quicktunnel running for localhost:%s\n" $port
    exit 1
fi