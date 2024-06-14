#!/bin/bash

trap cleanup EXIT

LISTEN_PORT=18384
METRICS_PORT="${SYNCTHING_METRICS_PORT:-28384}"
PROXY_PORT="${SYNCTHING_PORT_HOST:-8384}"
SERVICE_URL="${SYNCTHING_URL:-}"
QUICKTUNNELS=true

SERVICE_NAME="Syncthing (File Sync)"

function cleanup() {
    rm /run/http_ports/$PROXY_PORT > /dev/null 2>&1
    fuser -k -SIGTERM ${LISTEN_PORT}/tcp > /dev/null 2>&1 &
    wait -n
}

# Function to run command with retry
function run_with_retry() {
    until "$@"; do
        printf "Command failed. Retrying...\n"
        sleep 1
    done
}

function start() {
    source /opt/ai-dock/etc/environment.sh
    
    if [[ ${SERVERLESS,,} = "true" ]]; then
        printf "Refusing to start $SERVICE_NAME in serverless mode\n"
        exec sleep 6
    fi
    
    file_content="$(
      jq --null-input \
        --arg listen_port "${LISTEN_PORT}" \
        --arg metrics_port "${METRICS_PORT}" \
        --arg proxy_port "${PROXY_PORT}" \
        --arg service_name "${SERVICE_NAME}" \
        --arg service_url "${SERVICE_URL}" \
        '$ARGS.named'
    )"
    
    printf "%s\n" "$file_content" > /run/http_ports/$PROXY_PORT
    
    printf "Starting ${SERVICE_NAME}...\n"
    
    fuser -k -SIGKILL ${LISTEN_PORT}/tcp > /dev/null 2>&1 &
    wait -n
    
    syncthing generate

    sed -i '/^\s*<listenAddress>/d' "/home/${USER_NAME}/.local/state/syncthing/config.xml"

    syncthing --gui-address="127.0.0.1:${LISTEN_PORT}" --gui-apikey="${WEB_TOKEN}" &
    syncthing_pid=$!

    until curl --output /dev/null --silent --head --fail "http://127.0.0.1:${LISTEN_PORT}"; do
        printf "Waiting for syncthing server...\n"
        sleep 1
    done

    # Sometimes these commands fail despite the server being ready, so we use the run_with_retry function
    # Already behind proxy with auth
    run_with_retry syncthing cli --gui-address="127.0.0.1:${LISTEN_PORT}" --gui-apikey="${WEB_TOKEN}" config gui insecure-admin-access set true
    run_with_retry syncthing cli --gui-address="127.0.0.1:${LISTEN_PORT}" --gui-apikey="${WEB_TOKEN}" config gui insecure-skip-host-check set true
    run_with_retry syncthing cli --gui-address="127.0.0.1:${LISTEN_PORT}" --gui-apikey="${WEB_TOKEN}" config options raw-listen-addresses add "tcp://0.0.0.0:${SYNCTHING_TRANSPORT_PORT_HOST:-22999}"
    run_with_retry syncthing cli --gui-address="127.0.0.1:${LISTEN_PORT}" --gui-apikey="${WEB_TOKEN}" config options raw-listen-addresses add default

    wait $syncthing_pid
}

start 2>&1