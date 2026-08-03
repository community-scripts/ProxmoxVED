#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DIYgod/RSSHub

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
  python3 \
  redis-server
systemctl enable -q --now redis-server
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="pnpm@^10" setup_nodejs

fetch_and_deploy_gh_release "rsshub" "DIYgod/RSSHub" "tarball"

msg_info "Building RSSHub (Patience)"
cd /opt/rsshub
$STD pnpm install --frozen-lockfile
$STD pnpm build
msg_ok "Built RSSHub"

msg_info "Configuring RSSHub"
cat <<EOF >/opt/rsshub.env
NODE_ENV=production
PORT=1200
CACHE_TYPE=redis
REDIS_URL=redis://127.0.0.1:6379/
CACHE_EXPIRE=300
NODE_OPTIONS=--max-http-header-size=32768

# Restrict who may use this instance (recommended if reachable from outside):
#ACCESS_KEY=$(openssl rand -hex 16)
EOF
chmod 600 /opt/rsshub.env
msg_ok "Configured RSSHub"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rsshub.service
[Unit]
Description=RSSHub
Wants=network-online.target
After=network-online.target redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rsshub
EnvironmentFile=/opt/rsshub.env
ExecStart=/usr/bin/node dist/index.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rsshub
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
