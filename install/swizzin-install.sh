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

msg_custom "!" "$YELLOW" "WARNING: This script will run an external installer from a third-party source (swizzin.io)."
msg_custom "!" "$YELLOW" "You are about to execute code that is NOT maintained by our repository."
echo
read -r -p "Do you want to continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  msg_error "Aborted by user. No changes have been made."
  exit 1
fi
bash <(curl -sL s5n.sh)

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
