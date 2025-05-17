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

APP="Pulse"
APP_DIR="/opt/pulse-proxmox"
PULSE_USER="pulse"
SERVICE_NAME="pulse-monitor.service"

msg_info "Creating dedicated user pulse..."
if id pulse &>/dev/null; then
  msg_warning "User '${PULSE_USER}' already exists. Skipping creation."
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

msg_info "Setup ${APP}"
$STD git clone https://github.com/rcourtman/Pulse.git /opt/pulse-proxmox
cd /opt/pulse-proxmox
$STD npm install --unsafe-perm
cd /opt/pulse-proxmox/server
$STD npm install --unsafe-perm
cd /opt/pulse-proxmox
$STD npm run build:css
ENV_EXAMPLE="/opt/pulse-proxmox/.env.example"
ENV_FILE="${/opt/pulse-proxmox}/.env"
if [ -f "$ENV_EXAMPLE" ]; then
  if [ ! -s "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    msg_info "Created ${ENV_FILE} from example."
    sed -i 's|^PROXMOX_HOST=.*|PROXMOX_HOST=https://proxmox_host:8006|' "$ENV_FILE"
    sed -i 's|^PROXMOX_TOKEN_ID=.*|PROXMOX_TOKEN_ID=user@pam!tokenid|' "$ENV_FILE"
    sed -i 's|^PROXMOX_TOKEN_SECRET=.*|PROXMOX_TOKEN_SECRET=YOUR_API_SECRET_HERE|' "$ENV_FILE"
    sed -i 's|^PROXMOX_ALLOW_SELF_SIGNED_CERTS=.*|PROXMOX_ALLOW_SELF_SIGNED_CERTS=true|' "$ENV_FILE"
    sed -i 's|^PORT=.*|PORT=7655|' "$ENV_FILE"
    msg_warning "${ENV_FILE} created with placeholder values. Please edit it with your Proxmox details!"
  else
    msg_warning "${ENV_FILE} already exists. Skipping default configuration."
  fi
  chmod 600 "$ENV_FILE"
else
  msg_warning "${ENV_EXAMPLE} not found. Skipping environment configuration."
fi

msg_info "Setting permissions for /opt/pulse-proxmox..."
chown -R ${PULSE_USER}:${PULSE_USER} "/opt/pulse-proxmox"
find "/opt/pulse-proxmox" -type d -exec chmod 755 {} \;
find "/opt/pulse-proxmox" -type f -exec chmod 644 {} \;
chmod 600 "$ENV_FILE"
msg_ok "Set permissions."

msg_info "Saving installed version information..."
VERSION_TO_SAVE="${LATEST_RELEASE:-$(git rev-parse --short HEAD)}"
echo "${VERSION_TO_SAVE}" >/opt/${APP}_version.txt
msg_ok "Saved version info (${VERSION_TO_SAVE})."

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
systemctl enable -q --now pulse-monitor.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up apt cache..."
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned up."
