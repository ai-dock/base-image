#!/bin/false

# This file will be sourced in init.sh
# If you want to make environment variables avaiable globally:
# do export VAR_NAME; env-store VAR_NAME
# This will write to /opt/ai-dock/etc/environment.sh

function preflight_main() {
    preflight_do_something
}

function preflight_do_something() {
    printf "Empty preflight script...\n"
}

preflight_main "$@"