#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://blinko.space/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs

msg_info "Installing Bun"
export BUN_INSTALL="/root/.bun"
curl -fsSL https://bun.sh/install | $STD bash
ln -sf /root/.bun/bin/bun /usr/local/bin/bun
ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
msg_ok "Installed Bun"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="blinko" PG_DB_USER="blinko" setup_postgresql_db

fetch_and_deploy_gh_release "blinko" "blinkospace/blinko" "tarball"

msg_info "Setting up Blinko"
cd /opt/blinko
cat <<EOF >/opt/blinko/.env
NODE_ENV=production
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
NEXTAUTH_URL=http://${LOCAL_IP}:1111
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NEXT_PUBLIC_BASE_URL=http://${LOCAL_IP}:1111
EOF
$STD bun install
$STD bun run build:web
$STD bun run build:seed
$STD bun run prisma:generate
$STD bun run prisma:migrate:deploy
$STD bun run seed
msg_ok "Set up Blinko"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/blinko.service
[Unit]
Description=Blinko Note-Taking App
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/blinko
ExecStartPre=/bin/bash -c "mkdir -p /opt/blinko/server/public && cp -r /opt/blinko/dist/public/. /opt/blinko/server/public/"
ExecStart=/usr/local/bin/bun --env-file /opt/blinko/.env /opt/blinko/dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now blinko
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
