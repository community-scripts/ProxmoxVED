#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rcourtman/pulse

export SPINNER_PID=""

source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Pulse"
var_tags="monitoring;proxmox;dashboard"
var_cpu="1"
var_ram="1024"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"
PULSE_VERSION="1.6.4"  # Current version to install
COMMIT_HASH="7586c48f"  # Current commit hash of this script

header_info "$APP"
base_settings

variables
color
catch_errors

APPPATH="/opt/${NSAPP}"

function setup_locale_environment() {
    # Install locales package if needed
    pct exec ${CTID} -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y locales > /dev/null 2>&1"
    # Configure locales silently
    pct exec ${CTID} -- bash -c "sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen"
    pct exec ${CTID} -- bash -c "locale-gen > /dev/null 2>&1"
    # Set environment variables directly in container
    pct exec ${CTID} -- bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
    pct exec ${CTID} -- bash -c "echo 'LC_ALL=en_US.UTF-8' >> /etc/default/locale"
    pct exec ${CTID} -- bash -c "echo 'export LANG=en_US.UTF-8' >> /etc/profile"
    pct exec ${CTID} -- bash -c "echo 'export LC_ALL=en_US.UTF-8' >> /etc/profile"
    # Also set directly in current environment
    pct exec ${CTID} -- bash -c "export LANG=en_US.UTF-8 && export LC_ALL=en_US.UTF-8"
}

start
build_container
description

setup_locale_environment

msg_info "Setting up Pulse installation in the container"

pct exec ${CTID} -- bash -c "apt-get update > /dev/null 2>&1"
pct exec ${CTID} -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y curl git ca-certificates gnupg sudo build-essential > /dev/null 2>&1"
msg_ok "Core dependencies installed"

msg_info "Installing Node.js"
pct exec ${CTID} -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1"
pct exec ${CTID} -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs > /dev/null 2>&1"
msg_ok "Node.js installed"

msg_info "Creating application directory"
pct exec ${CTID} -- bash -c "mkdir -p /opt/${NSAPP}"
msg_ok "Application directory created"

msg_info "Downloading Pulse v${PULSE_VERSION} release"
pct exec ${CTID} -- bash -c "wget -qO- https://github.com/rcourtman/pulse/releases/download/v${PULSE_VERSION}/pulse-${PULSE_VERSION}.tar.gz | tar xz -C /opt/${NSAPP} --strip-components=1 > /dev/null 2>&1"
msg_ok "Release downloaded and extracted"

msg_info "Creating mock server service"
pct exec ${CTID} -- bash -c "cat > /etc/systemd/system/pulse-mock.service << 'EOFSVC'
[Unit]
Description=Pulse Mock Data Server
After=network.target
Before=pulse.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/${NSAPP}
Environment=NODE_ENV=production
Environment=MOCK_SERVER_PORT=7656
ExecStart=/usr/bin/node /opt/${NSAPP}/dist/mock/server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC"
msg_ok "Mock server service created"

msg_info "Setting up environment configuration"
pct exec ${CTID} -- bash -c "cat > /opt/${NSAPP}/.env.example << 'EOFENV'

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
EOFENV"

pct exec ${CTID} -- bash -c "cp /opt/${NSAPP}/.env.example /opt/${NSAPP}/.env"
msg_ok "Environment configuration created"

msg_info "Creating service files"
pct exec ${CTID} -- bash -c "cat > /etc/systemd/system/pulse.service << 'EOFSVC'
[Unit]
Description=Pulse for Proxmox Monitoring
After=network.target
After=pulse-mock.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/${NSAPP}
Environment=NODE_ENV=production
Environment=MOCK_SERVER_PORT=7656
ExecStart=/usr/bin/node /opt/${NSAPP}/dist/server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC"
msg_ok "Main service file created"

msg_info "Setting file permissions"
pct exec ${CTID} -- bash -c "chown -R root:root /opt/${NSAPP} && chmod -R 755 /opt/${NSAPP} && chmod 600 /opt/${NSAPP}/.env && chmod 644 /opt/${NSAPP}/.env.example"
msg_ok "File permissions set"

pct exec ${CTID} -- bash -c "echo '${PULSE_VERSION}' > /opt/${NSAPP}/${NSAPP}_version.txt"

msg_info "Creating update utility"
pct exec ${CTID} -- bash -c "echo 'bash -c \"\$(wget -qLO - https://github.com/rcourtman/ProxmoxVE/raw/${COMMIT_HASH}/ct/pulse.sh)\"' > /usr/bin/update && chmod +x /usr/bin/update"
msg_ok "Update utility created"

msg_info "Enabling and starting services"
pct exec ${CTID} -- bash -c "systemctl enable pulse-mock > /dev/null 2>&1 && systemctl start pulse-mock > /dev/null 2>&1"
pct exec ${CTID} -- bash -c "systemctl enable pulse > /dev/null 2>&1 && systemctl start pulse > /dev/null 2>&1"
msg_ok "Pulse services started"

msg_ok "Pulse installation complete"

if [ -z "${IP}" ]; then
  IP=$(pct exec ${CTID} ip a s dev eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")
  if [ -z "${IP}" ]; then
    IP=$(pct config ${CTID} | grep -E 'net0' | grep -oP '(?<=ip=)\d+(\.\d+){3}' || echo "")
    if [ -z "${IP}" ]; then
      sleep 5
      IP=$(pct exec ${CTID} hostname -I | awk '{print $1}' || echo "CONTAINER_IP")
    fi
  fi
fi

printf "\n"
echo -e "${BFR}${CM}${GN}${APP} is ready at: ${BGN}http://${IP}:7654${CL}\n"
