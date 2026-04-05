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
  git
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "puter" "HeyPuter/puter" "tarball"

msg_info "Building Application"
cd /opt/puter
$STD npm ci
cd /opt/puter/src/gui
$STD npm run build
cd /opt/puter
cp -r src/gui/dist dist
msg_ok "Built Application"

msg_info "Creating Directories"
mkdir -p /etc/puter /var/puter
msg_ok "Created Directories"

msg_info "Configuring Application"
cat <<EOF >/etc/puter/config.json
{
  "config_name": "proxmox",
  "domain": "${LOCAL_IP}",
  "http_port": 4100,
  "experimental_no_subdomain": true
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
Environment=CONFIG_PATH=/etc/puter
ExecStart=/usr/bin/npm start
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
