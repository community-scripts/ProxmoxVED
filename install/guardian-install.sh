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
  git \
  nodejs \
  npm \
  sqlite3 \
  unzip \
  curl
msg_ok "Installed Dependencies"

msg_info "Setup Guardian"
RELEASE=$(curl -fsSL https://api.github.com/repos/HydroshieldMKII/Guardian/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL -o "${RELEASE}.zip" "https://github.com/HydroshieldMKII/Guardian/archive/refs/tags/${RELEASE}.zip"
unzip -q "${RELEASE}.zip"

FOLDER_NAME=$(echo "${RELEASE}" | sed 's/^v//')
mv "Guardian-${FOLDER_NAME}/" "/opt/Guardian"

echo "${RELEASE}" >/opt/Guardian_version.txt
msg_ok "Setup Guardian"


msg_info "Building backend"
cd /opt/Guardian/backend
npm ci
npm run build
msg_ok "Built backend"

msg_info "Building frontend"
cd /opt/Guardian/frontend
npm ci
DEPLOYMENT_MODE=standalone npm run build
msg_ok "Built frontend"

msg_info "Creating Backend Service"
cat <<EOF >/etc/systemd/system/guardian-backend.service
[Unit]
Description=Guardian Backend
After=network.target

[Service]
WorkingDirectory=/opt/Guardian/backend
ExecStart=/usr/bin/node dist/main.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now guardian-backend
msg_ok "Created Backend Service"

msg_info "Creating Frontend Service"
cat <<EOF >/etc/systemd/system/guardian-frontend.service
[Unit]
Description=Guardian Frontend
After=guardian-backend.service network.target
Wants=guardian-backend.service

[Service]
WorkingDirectory=/opt/Guardian/frontend
Environment=DEPLOYMENT_MODE=standalone
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now guardian-frontend
msg_ok "Created Frontend Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f "${RELEASE}".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
