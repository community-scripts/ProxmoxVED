#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rcourtman/Pulse

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PULSE_USER="pulse"
SERVICE_NAME="pulse-monitor.service"

msg_info "Creating dedicated user pulse..."
if id pulse &>/dev/null; then
  msg_warn "User '${PULSE_USER}' already exists. Skipping creation."
else
  useradd -r -m -d /opt/pulse-home -s /bin/bash "$PULSE_USER"
  if useradd -r -m -d /opt/pulse-home -s /bin/bash "$PULSE_USER"; then
    msg_ok "User '${PULSE_USER}' created successfully."
  else
    msg_error "Failed to create user '${PULSE_USER}'."
    exit 1
  fi
fi

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  jq \
  diffutils
msg_ok "Installed Core Dependencies"

NODE_VERSION="20" NODE_MODULE="yarn@latest" install_node_and_modules

msg_info "Setup Pulse"
RELEASE=$(curl -fsSL https://api.github.com/repos/rcourtman/Pulse/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
temp_file=$(mktemp)
mkdir -p /opt/pulse-proxmox
curl -fsSL "https://github.com/rcourtman/Pulse/archive/refs/tags/v${RELEASE}.tar.gz" -o "$temp_file"
tar zxf "$temp_file" --strip-components=1 -C /opt/pulse-proxmox
cd /opt/pulse-proxmox
$STD npm install --unsafe-perm
cd /opt/pulse-proxmox/server
$STD npm install --unsafe-perm
cd /opt/pulse-proxmox
$STD npm run build:css
read -p "Proxmox Host (z. B. https://proxmox.example.com:8006): " PROXMOX_HOST
read -p "Proxmox Token ID (z. B. user@pam!mytoken): " PROXMOX_TOKEN_ID
read -p "Proxmox Token Secret: " PROXMOX_TOKEN_SECRET
read -p "Allow self-signed certs? (true/false): " PROXMOX_ALLOW_SELF_SIGNED_CERTS
read -p "Port (default: 7655): " PORT
PORT="${PORT:-7655}"

cat <<EOF >/opt/pulse-proxmox/.env
PROXMOX_HOST=${PROXMOX_HOST}
PROXMOX_TOKEN_ID=${PROXMOX_TOKEN_ID}
PROXMOX_TOKEN_SECRET=${PROXMOX_TOKEN_SECRET}
PROXMOX_ALLOW_SELF_SIGNED_CERTS=${PROXMOX_ALLOW_SELF_SIGNED_CERTS}
PORT=${PORT}
EOF
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Set up Pulse"

msg_info "Setting permissions for /opt/pulse-proxmox..."
chown -R ${PULSE_USER}:${PULSE_USER} "/opt/pulse-proxmox"
find "/opt/pulse-proxmox" -type d -exec chmod 755 {} \;
find "/opt/pulse-proxmox" -type f -exec chmod 644 {} \;
chmod 600 /opt/pulse-proxmox/.env
msg_ok "Set permissions."

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/pulse-monitor.service
[Unit]
Description=Pulse Monitoring Application
After=network.target

[Service]
Type=simple
User=pulse
Group=pulse
WorkingDirectory=/opt/pulse-proxmox
EnvironmentFile=/opt/pulse-proxmox/.env
ExecStart=/usr/bin/npm run start
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now pulse-monitor
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f "$temp_file"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
