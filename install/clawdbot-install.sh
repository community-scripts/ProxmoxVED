#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/clawdbot/clawdbot

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  git
msg_ok "Installed Dependencies"

NODE_VERSION="24" NODE_MODULE="clawdbot@latest" setup_nodejs
import_local_ip

msg_info "Configuring Clawdbot"
mkdir -p /opt/clawdbot/data
cat <<EOF >/opt/clawdbot/.env
NODE_ENV=production
GATEWAY_PORT=18791
GATEWAY_HOST=0.0.0.0
EOF
msg_ok "Configured Clawdbot"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/clawdbot.service
[Unit]
Description=Clawdbot Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/clawdbot
EnvironmentFile=/opt/clawdbot/.env
ExecStart=/usr/bin/clawdbot
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now clawdbot
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

