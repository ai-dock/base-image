#!/bin/bash

if [[ -z $2 ]]; then
    printf "Usage: set-web-credentials.sh username password\n"
    exit 1
fi

WEB_USER=$1
WEB_PASSWORD_HASH=$(hash-password.sh -p $2 -r 15)
export WEB_PASSWORD="********"

printf "Setting credentials and restarting proxy server...\n"
printf "%s %s" "$WEB_USER" "$WEB_PASSWORD_HASH" > /opt/caddy/etc/basicauth
supervisorctl restart caddy

