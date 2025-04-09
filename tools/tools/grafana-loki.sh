#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y gnupg2
msg_ok "Installed Dependencies"

msg_info "Setting up rclone"
wget https://github.com/rclone/rclone/releases/download/v1.69.1/rclone-v1.69.1-linux-amd64.de
dpkg -i rclone-v1.69.1-linux-amd64.deb
rclone rcd --rc-web-gui --rc-web-gui-no-open-browser --rc-addr :3000 --rc-user admin --rc-pass 12345
msg_ok "Set up Grafana"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
