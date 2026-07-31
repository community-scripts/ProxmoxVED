#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://logto.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="logto" PG_DB_USER="logto" setup_postgresql_db

fetch_and_deploy_gh_release "logto" "logto-io/logto" "prebuild" "latest" "/opt/logto" "logto.tar.gz"

msg_info "Configuring Logto"
DB_URL="postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}"
cat <<EOF >/opt/logto/.env
DB_URL=${DB_URL}
ENDPOINT=http://${LOCAL_IP}:3001
ADMIN_ENDPOINT=http://${LOCAL_IP}:3002
PORT=3001
ADMIN_PORT=3002
TRUST_PROXY_HEADER=0
EOF
msg_ok "Configured Logto"

msg_info "Seeding Database"
cd /opt/logto
DB_URL="${DB_URL}" $STD npm run cli db seed -- --swe
msg_ok "Seeded Database"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/logto.service
[Unit]
Description=Logto Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/logto/packages/core
EnvironmentFile=/opt/logto/.env
Environment=NODE_ENV=production
ExecStart=/usr/bin/node .
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now logto
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
