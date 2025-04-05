#!/usr/bin/env bash

# Copyright (c) 2024 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://coollabs.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    sudo \
    curl
msg_ok "Installed Dependencies"

msg_info "Installing Coolify"
wget -q https://cdn.coollabs.io/coolify/install.sh
chmod +x install.sh
$STD bash install.sh
msg_ok "Installed Coolify"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
