#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://netbird.io

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing NetBird Client"
curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --output /usr/share/keyrings/netbird-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' >/etc/apt/sources.list.d/netbird.list
$STD apt update
$STD apt install -y netbird
msg_ok "Installed NetBird Client"

msg_info "Enabling Service"
systemctl enable -q --now netbird
msg_ok "Enabled Service"

motd_ssh
customize
cleanup_lxc
