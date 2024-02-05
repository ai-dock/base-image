#!/bin/bash

if [[ -z $2 ]]; then
    printf "Usage: set-web-credentials.sh username password\n"
    exit 1
fi

export WEB_USER=$1
env-store WEB_USER
export WEB_PASSWORD=$2
env-store WEB_PASSWORD
export WEB_PASSWORD_B64="$(printf "%s:%s" "$WEB_USER" "$WEB_PASSWORD" | base64)"
env-store WEB_PASSWORD_B64

printf "Setting credentials and restarting proxy server...\n"

supervisorctl restart serviceportal
supervisorctl restart caddy
