#!/bin/bash

trap cleanup EXIT

function cleanup() {
    kill $(jobs -p) >/dev/null 2>&1
}

unset -v port
unset -v url

cert_path=/opt/caddy/tls/container.crt
key_path=/opt/caddy/tls/container.key
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

function validate_cert_and_key() {
  if openssl x509 -in "$cert_path" -noout > /dev/null 2>&1 && \
     openssl rsa -in "$key_path" -check -noout > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

function get_scheme() {
    if [[ ${WEB_ENABLE_HTTPS,,} == "true" ]] && validate_cert_and_key; then
        echo "https://"
    else
        echo "http://"
    fi
}



function get_url() {
    preset_url=$(jq -r ".service_url" "/run/http_ports/${port}")
    if [[ -n $preset_url ]]; then
        url="$preset_url"
    elif [[ ${DIRECT_ADDRESS_GET_WAN,,} == "true" ]]; then
        url="$(get_scheme)$(/opt/ai-dock/bin/external-ip-address):${port}"
    # Vast.ai
    elif env | grep 'VAST_TCP_PORT' > /dev/null 2>&1; then
        declare -n vast_mapped_port=VAST_TCP_PORT_${port}
        if [[ -n $vast_mapped_port ]]; then
            url="$(get_scheme)$(/opt/ai-dock/bin/external-ip-address):${vast_mapped_port}"
        else
            url="$(/opt/ai-dock/bin/cfqt-url -p $port)"
        fi
    # Runpod.io
    elif env | grep 'RUNPOD' > /dev/null 2>&1; then
        declare -n runpod_mapped_port=RUNPOD_TCP_PORT_${port}
        if [[ -n $runpod_mapped_port && -n $RUNPOD_PUBLIC_IP ]]; then
            url="$(get_scheme)${RUNPOD_PUBLIC_IP}:${runpod_mapped_port}"
        elif [[ -n $RUNPOD_POD_ID ]]; then
            url="$(get_scheme)${RUNPOD_POD_ID}-${port}.proxy.runpod.net"
        fi
    # Other cloud / local
    else
        url="$(get_scheme)${DIRECT_ADDRESS:-localhost}:${port}"
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