#!/usr/bin/env bash

# Copyright (c) 2024 community-scripts ORG
# Author: Arian Nasr (arian-nasr)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.freepbx.org/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc
msg_ok "Installed Dependencies"

msg_info "Installing FreePBX (Patience)"
wget -q https://raw.githubusercontent.com/FreePBX/sng_freepbx_debian_install/refs/heads/master/sng_freepbx_debian_install.sh
$STD bash ./sng_freepbx_debian_install.sh
msg_ok "Installed FreePBX"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf sng_freepbx_debian_install.sh
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
