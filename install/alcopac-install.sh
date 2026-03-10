#!/usr/bin/env bash
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://dev.alcopa.cc/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Base Dependencies"
$STD apt-get install -y unzip
msg_ok "Installed Base Dependencies"

msg_info "Installing Alcopac (Non-interactive)"
TEMP_INSTALL="$(mktemp)"
trap 'rm -f "$TEMP_INSTALL"' EXIT
$STD curl -fsSL https://dev.alcopa.cc/install -o "$TEMP_INSTALL"
$STD bash "$TEMP_INSTALL" install
msg_ok "Installed Alcopac"

motd_ssh
customize

cleanup_lxc
