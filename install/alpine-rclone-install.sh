#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rclone/rclone

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Rclone"
$STD apk add --no-cache rclone
msg_ok "Installed Rclone"

msg_info "Enabling Rclone Service"
$STD rc-update add rclone default
msg_ok "Enabled Rclone Service"

msg_info "Starting Rclone"
$STD rc-service rclone start
msg_ok "Started Rclone"

motd_ssh
customize
