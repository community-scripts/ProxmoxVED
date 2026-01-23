#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing RustyPaste"
$STD apk add --no-cache rustypaste rustypaste-openrc rustypaste-cli --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community
msg_ok "Installed RustyPaste"

msg_info "Configuring RustyPaste"
mkdir -p /var/lib/rustypaste
sed -i 's|^address = ".*"|address = "0.0.0.0:8000"|' /etc/rustypaste/config.toml
msg_ok "Configured RustyPaste"

msg_info "Creating Service"
$STD rc-update add rustypaste default
$STD rc-service rustypaste start
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
