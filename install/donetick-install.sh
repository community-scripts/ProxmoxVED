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

msg_info "Setup donetick"
RELEASE=$(curl -fsSL https://api.github.com/repos/donetick/donetick/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')

mkdir -p /opt/donetick
cd /opt/donetick

wget -q https://github.com/donetick/donetick/releases/download/${RELEASE}/donetick_Linux_x86_64.tar.gz
tar -xf donetick_Linux_x86_64.tar.gz

TOKEN=$(openssl rand -hex 16)
sed -i -e "s/change_this_to_a_secure_random_string_32_characters_long/${TOKEN}/g" config/selfhosted.yaml

echo "${RELEASE}" > /opt/donetick/donetick_version.txt
msg_ok "Setup donetick"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/donetick.service
[Unit]
Description=donetick Service
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
rm -rf /opt/donetick/donetick_Linux_x86_64.tar.gz
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned"

