#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aroldobossoni
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/decolua/9router

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
  python3
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "9router" "decolua/9router" "tarball" "latest" "/opt/9router"

msg_info "Building 9Router"
mkdir -p /var/lib/9router
cd /opt/9router
$STD npm install
DATA_DIR=/var/lib/9router NEXT_TELEMETRY_DISABLED=1 $STD npm run build
rm -rf /opt/9router-standalone
mkdir -p /opt/9router-standalone/.next /opt/9router-standalone/src /opt/9router-standalone/node_modules
cp -r .next/standalone/. /opt/9router-standalone/
cp -r .next/static /opt/9router-standalone/.next/static
cp -r public custom-server.js open-sse /opt/9router-standalone/
cp -r src/mitm /opt/9router-standalone/src/mitm
cp -r node_modules/node-forge node_modules/next /opt/9router-standalone/node_modules/
rm -rf /opt/9router
mv /opt/9router-standalone /opt/9router
msg_ok "Built 9Router"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/9router.service
[Unit]
Description=9Router Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/9router
Environment=NODE_ENV=production
Environment=PORT=20128
Environment=HOSTNAME=0.0.0.0
Environment=NEXT_TELEMETRY_DISABLED=1
Environment=DATA_DIR=/var/lib/9router
ExecStart=/usr/bin/node /opt/9router/custom-server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now 9router
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
