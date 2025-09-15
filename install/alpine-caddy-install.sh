#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: cobalt (cobaltgit)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://caddyserver.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Caddy"
$STD apk add --no-cache caddy caddy-openrc
msg_ok "Installed Caddy"

read -r -p "${TAB3}Would you like to install xCaddy Addon? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  msg_info "Setup xCaddy"
  $STD apk add --no-cache xcaddy
  $STD xcaddy build
  msg_ok "Setup xCaddy"
fi

msg_info "Enabling Caddy Service"
$STD rc-update add caddy default
msg_ok "Enabled Caddy Service"

msg_info "Starting Caddy"
$STD service caddy start
msg_ok "Started Caddy"

motd_ssh
customize
