#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Joseph Stubberfield (stubbers)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/librespeed/speedtest-rust

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Setup App
msg_info "Setup ${APPLICATION}"
RELEASE=$(curl -fsSL https://api.github.com/repos/librespeed/speedtest-rust/releases/latest | grep '"tag_name"' | sed -E 's/.*"tag_name": "v([^"]+).*/\1/')
curl -fsSL -o "librespeed-rs-x86_64-unknown-linux-gnu.deb" "https://github.com/librespeed/speedtest-rust/releases/download/v${RELEASE}/librespeed-rs-x86_64-unknown-linux-gnu.deb"
$STD dpkg -i "librespeed-rs-x86_64-unknown-linux-gnu.deb"
#
#
#
echo "${RELEASE}" >/opt/"${APPLICATION}"_version.txt
msg_ok "Setup ${APPLICATION}"

# Enable service
msg_info "Enabling Service"
systemctl enable -q --now speedtest_rs.service
msg_ok "Enabled Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f "librespeed-rs-x86_64-unknown-linux-gnu.deb"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"