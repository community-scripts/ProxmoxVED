#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.papermark.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="papermark" PG_DB_USER="papermark" setup_postgresql_db

fetch_and_deploy_gh_release "papermark" "mfts/papermark" "tarball"

msg_info "Setting up Papermark"
cd /opt/papermark
DB_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}"
cat <<EOF >/opt/papermark/.env
DATABASE_URL=${DB_URL}
POSTGRES_PRISMA_URL=${DB_URL}
POSTGRES_PRISMA_URL_NON_POOLING=${DB_URL}
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NEXTAUTH_URL=http://${LOCAL_IP}:3000
NEXT_PUBLIC_BASE_URL=http://${LOCAL_IP}:3000
NODE_ENV=production
EOF
$STD npm install
$STD npx prisma generate
$STD npx prisma migrate deploy
sed -i -E 's/\{\s*type:\s*"host"\s*\}/{ type: "host", value: ".*" }/g' /opt/papermark/next.config.* 2>/dev/null || true
$STD npm run build
msg_ok "Set up Papermark"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/papermark.service
[Unit]
Description=Papermark Document Sharing
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/papermark
EnvironmentFile=/opt/papermark/.env
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now papermark
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
