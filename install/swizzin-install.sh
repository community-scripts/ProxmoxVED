#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: EEJoshua
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://swizzin.ltd/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl wget gnupg lsb-release
msg_ok "Dependencies installed"
echo -e "Launching upstream Swizzin installer..."
bash <(curl -sL s5n.sh)
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_ok "Swizzin base installation complete.  Re‑login and run 'sudo box' to add apps."
