#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Hlushok
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://dev.alcopa.cc/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Alcopac"
msg_warn "This script will install Alcopac using a third-party installer from dev.alcopa.cc"
$STD bash <(curl -fsSL https://dev.alcopa.cc/install) install
msg_ok "Installed Alcopac"

motd_ssh
customize

cleanup_lxc
