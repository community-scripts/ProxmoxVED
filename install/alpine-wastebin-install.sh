#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: cobaltgit (cobalt)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/matze/wastebin

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apk add --no-cache zstd
msg_ok "Installed dependencies"

msg_info "Installing Wastebin"
temp_file=$(mktemp)
RELEASE=$(curl -fsSL https://api.github.com/repos/matze/wastebin/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL "https://github.com/matze/wastebin/releases/download/${RELEASE}/wastebin_${RELEASE}_x86_64-unknown-linux-musl.tar.zst" -o "$temp_file"
mkdir -p /opt/wastebin
zstd -dc $temp_file | tar x -C /opt/wastebin wastebin wastebin-ctl
chmod +x /opt/wastebin/wastebin /opt/wastebin/wastebin-ctl

mkdir -p /opt/wastebin-data
cat <<EOF >/opt/wastebin-data/.env
WASTEBIN_DATABASE_PATH=/opt/wastebin-data/wastebin.db
WASTEBIN_CACHE_SIZE=1024
WASTEBIN_HTTP_TIMEOUT=30
WASTEBIN_SIGNING_KEY=$(openssl rand -hex 32)
WASTEBIN_PASTE_EXPIRATIONS=0,600,3600=d,86400,604800,2419200,29030400
EOF
echo "${RELEASE}" >~/.wastebin

msg_ok "Installed Wastebin"

msg_info "Creating Service"
cat <<EOF >/etc/init.d/wastebin
#!/sbin/openrc-run

name="wastebin"
description="Start Wastebin Service"

command="/opt/wastebin/wastebin"
command_background="yes"
pidfile="/var/run/wastebin.pid"
directory="/opt/wastebin"

depend() {
    need net
    after logger
}

start_pre() {
    if [ -f "/opt/wastebin-data/.env" ]; then
        export $(xargs < "/opt/wastebin-data/.env")
    fi
}
EOF
chmod +x /etc/init.d/wastebin
$STD rc-update add wastebin default
$STD rc-service wastebin start
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f $temp_file
msg_ok "Cleaned"

