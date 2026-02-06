#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bzumhagen
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Wetzel402/Skylite-UX

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  openssl
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
NODE_VERSION="20" setup_nodejs

PG_DB_NAME="skylite" PG_DB_USER="skylite" PG_DB_SCHEMA_PERMS="true" setup_postgresql_db

msg_info "Installing ${APPLICATION}"
$STD git clone https://github.com/Wetzel402/Skylite-UX.git /opt/skylite-ux
msg_ok "Installed ${APPLICATION}"

msg_info "Configuring ${APPLICATION}"
cat <<EOF >/opt/skylite-ux/.env
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
NODE_ENV=production
HOST=0.0.0.0
NUXT_PUBLIC_TZ=Etc/UTC
NUXT_PUBLIC_LOG_LEVEL=warn
EOF
msg_ok "Configured ${APPLICATION}"

msg_info "Building ${APPLICATION}"
cd /opt/skylite-ux
$STD npm ci
$STD npx prisma generate
$STD npm run build
msg_ok "Built ${APPLICATION}"

msg_info "Running Database Migrations"
cd /opt/skylite-ux
$STD npx prisma migrate deploy
msg_ok "Database Migrations Complete"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/skylite-ux.service
[Unit]
Description=Skylite-UX
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/skylite-ux
EnvironmentFile=/opt/skylite-ux/.env
ExecStart=/usr/bin/node /opt/skylite-ux/.output/server/index.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now skylite-ux
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
