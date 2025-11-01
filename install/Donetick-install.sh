#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: fstof
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/donetick/donetick

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt install -y \
  ca-certificates \
  libc6-compat
msg_ok "Installed Dependencies"

msg_info "Setup Donetick"
RELEASE=$(curl -fsSL https://api.github.com/repos/donetick/donetick/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')

mkdir -p /opt/donetick
cd /opt/donetick
curl -fsSL "https://github.com/donetick/donetick/releases/download/${RELEASE}/donetick_Linux_x86_64.tar.gz" | tar -xz -C .

echo "${RELEASE}" > /opt/donetick/donetick_version.txt
msg_ok "Setup Donetick"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/donetick.service
[Unit]
Description=Donetick Service
After=network.target

[Service]
Environment="DT_ENV=selfhosted"
WorkingDirectory=/opt/donetick
ExecStart=/opt/donetick/donetick
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now donetick
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned"
