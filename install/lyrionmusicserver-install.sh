#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://lyrion.org/getting-started/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Lyrion Music Server"

DEB_URL=$(curl -s 'https://lyrion.org/getting-started/' | grep -oP '<a\s[^>]*href="\K[^"]*amd64\.deb(?="[^>]*>)' | head -n 1)
LYRION_VERSION=$(echo "$DEB_URL" | grep -oP 'lyrionmusicserver_\K[0-9.]+(?=_amd64\.deb)')
DEB_FILE="/tmp/lyrionmusicserver_${LYRION_VERSION}_amd64.deb"
curl -fsSL -o "$DEB_FILE" "$DEB_URL"
$STD apt install "$DEB_FILE" -y

msg_ok "Installed Lyrion Music Server v${LYRION_VERSION}"

motd_ssh
customize

msg_info "Cleaning up"
$STD rm -f "$DEB_FILE"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
