#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Giovanni `evilaliv3` Pellerano
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/globaleaks/globaleaks-whistleblowing-software

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setup GlobaLeaks"
$STD bash <(curl -fsSL https://deb.globaleaks.org//install.sh) -y
msg_ok "Setup GlobaLeaks"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
