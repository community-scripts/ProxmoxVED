#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: johnpc
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/johnpc/subsyncarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  ffmpeg \
  python3 \
  python3-pip \
  python3-venv \
  pipx \
  build-essential \
  cron
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
fetch_and_deploy_gh_release "subsyncarr" "johnpc/subsyncarr" "tarball"

msg_info "Building ${APPLICATION}"
cd /opt/subsyncarr
$STD npm ci --ignore-scripts
$STD npm rebuild better-sqlite3
$STD npm run build
msg_ok "Built ${APPLICATION}"

msg_info "Installing Subtitle Sync Engines"
$STD pipx install ffsubsync
$STD pipx inject ffsubsync 'setuptools<82'
$STD pipx install autosubsync
$STD pipx inject autosubsync 'setuptools<82'
cp /opt/subsyncarr/bin/alass /usr/local/bin/alass
chmod +x /usr/local/bin/alass
msg_ok "Installed Subtitle Sync Engines"

msg_info "Configuring ${APPLICATION}"
mkdir -p /opt/subsyncarr/data
cat <<EOF >/opt/subsyncarr/.env
CRON_SCHEDULE=0 0 * * *
NODE_OPTIONS=--max-old-space-size=512
EOF
msg_ok "Configured ${APPLICATION}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/subsyncarr.service
[Unit]
Description=Subsyncarr - Automated Subtitle Synchronization
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/subsyncarr
EnvironmentFile=/opt/subsyncarr/.env
ExecStart=/usr/bin/node --optimize-for-size /opt/subsyncarr/dist/index-server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now subsyncarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
