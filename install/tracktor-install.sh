#!/usr/bin/env bash

# Copyright (c) 2025 Community Scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://tracktor.bytedge.in

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_nodejs
fetch_and_deploy_gh_release "tracktor" "javedh-dev/tracktor" 

msg_info "Configuring Tracktor"
cd /opt/tracktor
rm package-lock.json
$STD npm install
$STD npm run build
mkdir /opt/tracktor-data
cat <<EOF >/opt/tracktor.env
NODE_ENV=production
PUBLIC_DEMO_MODE=false
PUBLIC_API_BASE_URL=/
DB_PATH=/opt/tracktor-data/vehicles.db
PORT=3000
EOF
msg_ok "Configured Tracktor"

msg_info "Creating service"
cat <<EOF >/etc/systemd/system/tracktor.service
[Unit]
Description=Tracktor Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/tracktor
EnvironmentFile=/opt/tracktor.env
ExecStart=/usr/bin/npm start

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now tracktor
msg_ok "Created service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
