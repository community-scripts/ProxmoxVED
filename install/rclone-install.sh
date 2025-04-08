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
$STD apt-get install -y \
  gnupg2 \
  fuse
msg_ok "Installed Dependencies"

msg_info "Installing rclone"
wget https://downloads.rclone.org/v1.69.1/rclone-v1.69.1-linux-amd64.deb
dpkg -i rclone-v1.69.1-linux-amd64.deb
msg_ok "Installed rclone"

cat <<EOF >/etc/systemd/system/rclone-web.service
[Unit]
Description=Rclone Web GUI
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/rclone rcd --rc-web-gui --rc-web-gui-no-open-browser --rc-addr :3000 --rc-user admin --rc-pass 12345
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now rclone-web

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
