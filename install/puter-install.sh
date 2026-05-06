#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/HeyPuter/puter

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  git \
  python3
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "puter" "HeyPuter/puter" "tarball"

msg_info "Building Application"
cd /opt/puter
$STD npm ci
$STD npm run build
msg_ok "Built Application"

msg_info "Creating Directories"
mkdir -p /etc/puter /var/puter
msg_ok "Created Directories"

msg_info "Configuring Application"
cat <<EOF >/etc/puter/config.json
{
  "config_name": "proxmox",
  "domain": "${LOCAL_IP}",
  "protocol": "http",
  "http_port": 4100,
  "experimental_no_subdomain": true,
  "services": {
    "database": {
      "engine": "sqlite",
      "path": "puter-database.sqlite"
    }
  }
}
EOF
msg_ok "Configured Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/puter.service
[Unit]
Description=Puter
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/puter
Environment=PUTER_CONFIG_PATH=/etc/puter/config.json
ExecStart=/usr/bin/node --enable-source-maps -r /opt/puter/dist/src/backend/telemetry.js /opt/puter/dist/src/backend/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now puter
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
