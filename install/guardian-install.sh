#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: HydroshieldMKII
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/HydroshieldMKII/Guardian

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
  ca-certificates \
  gnupg \
  lsb-release
msg_ok "Installed Dependencies"

# Install Docker
msg_info "Installing Docker"
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
$STD apt-get update
$STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
msg_ok "Installed Docker"

# Setup Guardian
msg_info "Setting up Guardian"
mkdir -p /opt/Guardian
cd /opt/Guardian

# Download docker-compose.yml from repository
RELEASE=$(curl -fsSL https://api.github.com/repos/HydroshieldMKII/Guardian/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL -o docker-compose.yml "https://raw.githubusercontent.com/HydroshieldMKII/Guardian/main/docker-compose.example.yml"

# Create data directory for persistent storage
mkdir -p data

echo "${RELEASE}" >/opt/Guardian_version.txt
msg_ok "Setup Guardian"

# Start Guardian with Docker Compose
msg_info "Starting Guardian"
cd /opt/Guardian
docker compose up -d
msg_ok "Started Guardian"

# Create systemd service to manage Docker Compose
msg_info "Creating Guardian Service"
cat <<EOF >/etc/systemd/system/guardian.service
[Unit]
Description=Guardian Docker Compose
Requires=docker.service
After=docker.service
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/Guardian
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
systemctl enable guardian
msg_ok "Created Guardian Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
