#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rcourtman/pulse

# Import Functions and Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Set constants
APP="Pulse"
NSAPP=$(echo $APP | tr '[:upper:]' '[:lower:]')
PULSE_VERSION="1.6.4"
COMMIT_HASH="a5b1d05"

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  git \
  ca-certificates \
  gnupg \
  build-essential \
  locales
msg_ok "Installed Dependencies"

# Setup locale environment
msg_info "Setting up locale environment"
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen > /dev/null 2>&1
echo 'LANG=en_US.UTF-8' > /etc/default/locale
echo 'LC_ALL=en_US.UTF-8' >> /etc/default/locale
echo 'export LANG=en_US.UTF-8' >> /etc/profile
echo 'export LC_ALL=en_US.UTF-8' >> /etc/profile
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
msg_ok "Locale environment configured"

# Installing Node.js
msg_info "Installing Node.js"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
$STD apt-get install -y nodejs
msg_ok "Node.js installed"

# Creating application directory
msg_info "Creating application directory"
mkdir -p /opt/${NSAPP}
msg_ok "Application directory created"

# Downloading release
msg_info "Downloading Pulse v${PULSE_VERSION} release"
wget -qO- https://github.com/rcourtman/pulse/releases/download/v${PULSE_VERSION}/pulse-${PULSE_VERSION}.tar.gz | tar xz -C /opt/${NSAPP} --strip-components=1 > /dev/null 2>&1
msg_ok "Release downloaded and extracted"

# Creating mock server service
msg_info "Creating mock server service"
cat > /etc/systemd/system/pulse-mock.service << 'EOFSVC'
[Unit]
Description=Pulse Mock Data Server
After=network.target
Before=pulse.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pulse
Environment=NODE_ENV=production
Environment=MOCK_SERVER_PORT=7656
ExecStart=/usr/bin/node /opt/pulse/dist/mock/server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC
msg_ok "Mock server service created"

# Setting up environment configuration
msg_info "Setting up environment configuration"
cat > /opt/${NSAPP}/.env.example << 'EOFENV'
PROXMOX_NODE_1_NAME=pve
PROXMOX_NODE_1_HOST=https://your-proxmox-ip:8006
PROXMOX_NODE_1_TOKEN_ID=root@pam!pulse
PROXMOX_NODE_1_TOKEN_SECRET=your-token-secret

IGNORE_SSL_ERRORS=true
NODE_TLS_REJECT_UNAUTHORIZED=0
API_RATE_LIMIT_MS=2000
API_TIMEOUT_MS=90000
API_RETRY_DELAY_MS=10000

USE_MOCK_DATA=true
MOCK_DATA_ENABLED=true
MOCK_SERVER_PORT=7656

MOCK_CLUSTER_ENABLED=true
MOCK_CLUSTER_NAME=mock-cluster
EOFENV

cp /opt/${NSAPP}/.env.example /opt/${NSAPP}/.env
msg_ok "Environment configuration created"

# Creating service files
msg_info "Creating service files"
cat > /etc/systemd/system/pulse.service << 'EOFSVC'
[Unit]
Description=Pulse for Proxmox Monitoring
After=network.target
After=pulse-mock.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pulse
Environment=NODE_ENV=production
Environment=MOCK_SERVER_PORT=7656
ExecStart=/usr/bin/node /opt/pulse/dist/server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC
msg_ok "Main service file created"

# Setting file permissions
msg_info "Setting file permissions"
chown -R root:root /opt/${NSAPP}
chmod -R 755 /opt/${NSAPP}
chmod 600 /opt/${NSAPP}/.env
chmod 644 /opt/${NSAPP}/.env.example
msg_ok "File permissions set"

# Save version information
echo "${PULSE_VERSION}" > /opt/${NSAPP}/${NSAPP}_version.txt

# Creating update utility
msg_info "Creating update utility"
echo "bash -c \"\$(wget -qLO - https://github.com/community-scripts/ProxmoxVED/raw/${COMMIT_HASH}/ct/pulse.sh)\"" > /usr/bin/update
chmod +x /usr/bin/update
msg_ok "Update utility created"

# Starting services
msg_info "Enabling and starting services"
systemctl enable pulse-mock > /dev/null 2>&1
systemctl start pulse-mock > /dev/null 2>&1
systemctl enable pulse > /dev/null 2>&1
systemctl start pulse > /dev/null 2>&1
msg_ok "Pulse services started"

msg_ok "Pulse installation complete"

motd_ssh
customize

echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7654${CL}"
