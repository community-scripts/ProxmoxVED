#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://lemonade-server.ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
APP="Lemonade"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "lemonade" "lemonade-sdk/lemonade" "binary"

msg_info "Configuring Lemonade Server"
mkdir -p /opt/lemonade
cat <<EOF >/opt/lemonade/.env
LEMONADE_HOST=0.0.0.0
LEMONADE_PORT=8000
LEMONADE_LOG_LEVEL=info
EOF
msg_ok "Configured Lemonade Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/lemonade-server.service
[Unit]
Description=Lemonade Server - LLM Inference Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lemonade
EnvironmentFile=/opt/lemonade/.env
ExecStart=/usr/bin/lemonade-server serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now lemonade-server
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc