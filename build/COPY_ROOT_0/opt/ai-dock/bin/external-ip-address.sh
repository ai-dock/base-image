#!/bin/bash

current_time=$(date +%s)
cache_file="/tmp/external_ip_address"
cache_max_age=${EXTERNAL_IP_CACHE_SECS:-900}

if [[ -f $cache_file ]]; then
    file_mod_time=$(stat -c %Y "$cache_file")
    if [[ $((current_time - file_mod_time)) -lt $cache_max_age ]]; then
        ip=$(cat "$cache_file")
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "$ip"
            exit 0
        fi
    fi
fi

# Fetch new IP address
ip="$(dig whoami.cloudflare ch txt @1.1.1.1 +short | tr -d '"')"
[[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || ip="$(dig myip.opendns.com @resolver1.opendns.com +short)"
[[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || ip=$(curl -s ifconfig.me)

# Cache the IP address
echo "$ip" | tee "$cache_file"
