#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/john30/ebusd

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setting up ebusd Repository"
setup_deb822_repo \
  "ebusd" \
  "https://raw.githubusercontent.com/john30/ebusd-debian/master/ebusd.gpg" \
  "https://repo.ebusd.eu/apt/default/bookworm/" \
  "bookworm" \
  "main"
$STD apt update
msg_ok "ebusd Repository setup successfully"

msg_info "Installing ebusd"
$STD apt install -y ebusd
msg_ok "Installed ebusd"

msg_info "Follow below instructions to make the daemon autostart:"
msg_info "1. Edit '/etc/default/ebusd' if necessary (especially if your device is not '/dev/ttyUSB0')"
msg_info "2. Start the daemon with 'systemctl start ebusd'"
msg_info "3. Check the daemon status with 'systemctl status ebusd'"
msg_info "4. Check the log file '/var/log/ebusd.log'"
msg_info "5. Make the daemon autostart with 'systemctl enable ebusd'"

motd_ssh
customize
cleanup_lxc
