#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Giovanni `evilaliv3` Pellerano
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/globaleaks/globaleaks-whistleblowing-software

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
init_error_traps
setting_up_container
network_check
update_os

msg_info "Setup GlobaLeaks"
curl -fsSL https://deb.globaleaks.org/globaleaks.asc | gpg --dearmor >/etc/apt/trusted.gpg.d/globaleaks.asc
echo "deb [signed-by=/etc/apt/trusted.gpg.d/globaleaks.asc] http://deb.globaleaks.org bookworm main" >/etc/apt/sources.list.d/globaleaks.list
$STD apt-get update
$STD apt-get -y install globaleaks
msg_ok "Setup GlobaLeaks"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
