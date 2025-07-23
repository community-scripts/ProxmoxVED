#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Cleanuparr/Cleanuparr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
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
  mc \
  unzip
msg_ok "Installed Dependencies"

msg_info "Installing Cleanuparr"
RELEASE=$(curl -fsSL https://api.github.com/repos/Cleanuparr/Cleanuparr/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
mkdir -p /opt/cleanuparr
cd /opt/cleanuparr
curl -fsSLO "https://github.com/Cleanuparr/Cleanuparr/releases/download/v${RELEASE}/Cleanuparr-${RELEASE}-linux-amd64.zip"
unzip -q "Cleanuparr-${RELEASE}-linux-amd64.zip"
rm -f "Cleanuparr-${RELEASE}-linux-amd64.zip"
chmod +x /opt/cleanuparr/Cleanuparr
msg_ok "Installed Cleanuparr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/cleanuparr.service
[Unit]
Description=Cleanuparr Daemon
After=syslog.target network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cleanuparr
ExecStart=/opt/cleanuparr/Cleanuparr
Restart=on-failure
RestartSec=5
Environment="PORT=11011"
Environment="CONFIG_DIR=/opt/cleanuparr/config"

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now cleanuparr
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"