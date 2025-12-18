#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: TechHutTV
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://netbird.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  ca-certificates \
  gnupg
msg_ok "Installed Dependencies"

msg_info "Setting up NetBird Repository"
curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor -o /usr/share/keyrings/netbird-archive-keyring.gpg
chmod 0644 /usr/share/keyrings/netbird-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' | tee /etc/apt/sources.list.d/netbird.list >/dev/null
$STD apt-get update
msg_ok "Set up NetBird Repository"

msg_info "Installing NetBird"
$STD apt-get install -y netbird
msg_ok "Installed NetBird"

msg_info "Enabling NetBird Service"
$STD systemctl enable --now netbird
msg_ok "Enabled NetBird Service"

motd_ssh
customize
cleanup_lxc
