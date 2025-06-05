#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/arunavo4/gitea-mirror

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
  build-essential \
  openssl \
  git
msg_ok "Installed Dependencies"

msg_info "Installing Bun"
export BUN_INSTALL=/opt/bun
curl -fsSL https://bun.sh/install | $STD bash
ln -sf /opt/bun/bin/bun /usr/local/bin/bun
ln -sf /opt/bun/bin/bun /usr/local/bin/bunx
msg_ok "Installed Bun"

msg_info "Setting up PostgreSQL Database"
DB_NAME=nimbus
DB_USER=nimbus
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
APP_SECRET=$(openssl rand -base64 32)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "Nimbus-Credentials"
  echo "Nimbus Database User: $DB_USER"
  echo "Nimbus Database Password: $DB_PASS"
  echo "Nimbus Database Name: $DB_NAME"
} >>~/nimbus.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Installing nimbus"
cd /opt
git clone https://github.com/logscore/Nimbus.git
cd /opt/Nimbus
$STD bun install
$STD bun run build
$STD bun run manage-db init
msg_ok "Installed gitea-mirror"

msg_info "Creating Services"
JWT_SECRET=$(openssl rand -hex 32)
cat <<EOF >/etc/systemd/system/gitea-mirror.service
[Unit]
Description=Gitea Mirror
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/gitea-mirror
ExecStart=/usr/local/bin/bun dist/server/entry.mjs
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production
Environment=HOST=0.0.0.0
Environment=PORT=4321
Environment=DATABASE_URL=file:/opt/gitea-mirror/data/gitea-mirror.db
Environment=JWT_SECRET=${JWT_SECRET}
[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now gitea-mirror
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
