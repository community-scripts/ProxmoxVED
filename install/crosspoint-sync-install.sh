#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Boisti13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/crosspoint-reader/crosspoint-sync

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_branch "crosspoint-sync" "crosspoint-reader/crosspoint-sync"

msg_info "Building CrossPoint-Sync"
cd /opt/crosspoint-sync
$STD npm ci
$STD npm run build
$STD npm prune --omit=dev
msg_ok "Built CrossPoint-Sync"

msg_info "Configuring CrossPoint-Sync"
mkdir -p /opt/crosspoint-sync-data
cat <<EOF >/opt/crosspoint-sync.env
NODE_ENV=production
PORT=8080
DATABASE_PATH=/opt/crosspoint-sync-data/crosspoint.db
REGISTRATION_DISABLED=false
EOF
chmod 600 /opt/crosspoint-sync.env
msg_ok "Configured CrossPoint-Sync"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/crosspoint-sync.service
[Unit]
Description=crosspoint-sync
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/crosspoint-sync
EnvironmentFile=/opt/crosspoint-sync.env
ExecStart=/usr/bin/node dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now crosspoint-sync
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
