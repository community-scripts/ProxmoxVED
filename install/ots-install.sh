#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Luzifer/ots

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  redis-server
msg_ok "Installed Dependencies"

msg_info "Installing OTS"
fetch_and_deploy_gh_release "ots" "Luzifer/ots" "prebuild" "latest" "/opt/ots" "ots_linux_amd64.tgz"
cat <<EOF >/opt/ots/env
LISTEN=0.0.0.0:3000
REDIS_URL=redis://127.0.0.1:6379
SECRET_EXPIRY=604800
STORAGE_TYPE=redis
EOF
msg_ok "Installed OTS"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/ots.service
[Unit]
Description=One-Time-Secret Service
After=network-online.target
Requires=network-online.target

[Service]
EnvironmentFile=/opt/ots/env
ExecStart=/opt/ots/ots
Restart=Always
RestartSecs=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
