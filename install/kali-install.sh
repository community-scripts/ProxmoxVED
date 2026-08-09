#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Otto Zoeke (FairTradeOrange)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.kali.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Kali Headless"
$STD apt install -y kali-linux-headless
msg_ok "Installed Kali Headless"

motd_ssh
customize
cleanup_lxc