#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mauriceboe/TREK

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "trek" "mauriceboe/TREK" "tarball"

msg_info "Building Client"
cd /opt/trek/client
$STD npm ci
$STD npm run build
msg_ok "Built Client"

msg_info "Setting up Server"
cd /opt/trek/server
$STD npm ci
mkdir -p /opt/trek/server/public
cp -r /opt/trek/client/dist/* /opt/trek/server/public/
cp -r /opt/trek/client/public/fonts /opt/trek/server/public/fonts 2>/dev/null || true
mkdir -p /opt/trek/{data/logs,uploads/{files,covers,avatars,photos}}
ln -sf /opt/trek/data /opt/trek/server/data
ln -sf /opt/trek/uploads /opt/trek/server/uploads
ENCRYPTION_KEY=$(openssl rand -hex 32)
ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)
cat <<EOF >/opt/trek/server/.env
NODE_ENV=production
PORT=3000
ENCRYPTION_KEY=${ENCRYPTION_KEY}
COOKIE_SECURE=false
FORCE_HTTPS=false
LOG_LEVEL=info
TZ=UTC
EOF
msg_ok "Set up Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/trek.service
[Unit]
Description=TREK Travel Planner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/trek/server
EnvironmentFile=/opt/trek/server/.env
ExecStart=/usr/bin/node --import tsx src/index.ts
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now trek
msg_ok "Created Service"

msg_info "Waiting for TREK to initialize"
for i in $(seq 1 30); do
  if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
cd /opt/trek/server
$STD node -e "
const Database = require('better-sqlite3');
const bcrypt = require('bcryptjs');
const db = new Database('./data/travel.db');
const hash = bcrypt.hashSync('${ADMIN_PASSWORD}', 12);
db.prepare('UPDATE users SET password_hash = ?, must_change_password = 0 WHERE email = ?').run(hash, 'admin@trek.local');
db.close();
"
{
  echo ""
  echo "TREK Admin Credentials"
  echo "Email:    admin@trek.local"
  echo "Password: ${ADMIN_PASSWORD}"
  echo ""
} >>~/trek.creds
msg_ok "TREK initialized"
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
