#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/steveiliop56/tinyauth

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add \
  npm \
  curl \
  go
msg_ok "Installed Dependencies"

msg_info "Installing tinyauth"
temp_file=$(mktemp)
$STD npm install -g bun
mkdir -p /opt/tinyauth
RELEASE=$(curl -s https://api.github.com/repos/steveiliop56/tinyauth/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL https://github.com/steveiliop56/tinyauth/archive/refs/tags/v3.1.0.tar.gz -o $temp_file
tar -xzf $temp_file -C /opt/tinyauth --strip-components=1
cd /opt/tinyauth/site
$STD bun install
$STD bun run build
mv dist /opt/tinyauth/internal/assets/
cd /opt/tinyauth
$STD go mod download
CGO_ENABLED=0 go build -ldflags "-s -w"
SECRET=$(head -c 32 /dev/urandom | xxd -p -c 32)
msg_ok "Installed tinyauth"

msg_info "Enabling tinyauth Service"
service_path="/etc/init.d/tinyauth"

echo '#!/sbin/openrc-run
description="tinyauth Service"

command="/opt/tinyauth/tinyauth"
command_args="--secret=$SECRET --users=admin@example.com:$apr1$n61ztxfk$0f/uGQFxnB.FBa5cxgqNg."
command_user="root"
pidfile="/var/run/tinyauth.pid"

depend() {
    use net
}' >$service_path

chmod +x $service_path
$STD rc-update add tinyauth default
msg_ok "Enabled tinyauth Service"

msg_info "Starting tinyauth"
$STD service tinyauth start
msg_ok "Started tinyauth"

motd_ssh
customize
