#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: lucasfell
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ghostfol.io/

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
  build-essential \
  python3 \
  openssl \
  curl \
  ca-certificates
msg_ok "Installed Dependencies"

PG_VERSION="15" setup_postgresql

msg_info "Installing Redis"
$STD apt-get install -y redis-server
systemctl enable -q --now redis-server
msg_ok "Installed Redis"

NODE_VERSION="22" setup_nodejs

msg_info "Setting up Database"
DB_NAME=ghostfolio
DB_USER=ghostfolio
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
REDIS_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
ACCESS_TOKEN_SALT=$(openssl rand -base64 32)
JWT_SECRET_KEY=$(openssl rand -base64 32)

$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
$STD sudo -u postgres psql -c "ALTER USER $DB_USER CREATEDB;"

{
  echo "Ghostfolio Credentials"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo "Database Name: $DB_NAME"
  echo "Redis Password: $REDIS_PASS"
  echo "Access Token Salt: $ACCESS_TOKEN_SALT"
  echo "JWT Secret Key: $JWT_SECRET_KEY"
} >>~/ghostfolio.creds
msg_ok "Set up Database"

msg_info "Configuring Redis"
sed -i "s/# requirepass foobared/requirepass $REDIS_PASS/" /etc/redis/redis.conf
systemctl restart redis-server
msg_ok "Configured Redis"

msg_info "Cloning Ghostfolio"
cd /opt
$STD git clone https://github.com/ghostfolio/ghostfolio.git
cd ghostfolio
RELEASE=$(git describe --tags --abbrev=0)
git checkout $RELEASE
msg_ok "Cloned Ghostfolio $RELEASE"

msg_info "Installing Ghostfolio Dependencies"
$STD npm ci
msg_ok "Installed Dependencies"

msg_info "Building Ghostfolio"
$STD npm run build:production
msg_ok "Built Ghostfolio"

msg_info "Setting up Environment"
cat <<EOF >/opt/ghostfolio/.env
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME?connect_timeout=300&sslmode=prefer
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASS
ACCESS_TOKEN_SALT=$ACCESS_TOKEN_SALT
JWT_SECRET_KEY=$JWT_SECRET_KEY
NODE_ENV=production
PORT=3333
HOST=0.0.0.0
EOF
msg_ok "Set up Environment"

msg_info "Running Database Migrations"
cd /opt/ghostfolio/dist/apps/api
$STD npx prisma migrate deploy
$STD npx prisma db seed
msg_ok "Database Migrations Complete"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/ghostfolio.service
[Unit]
Description=Ghostfolio Investment Tracker
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ghostfolio/dist/apps/api
Environment=NODE_ENV=production
EnvironmentFile=/opt/ghostfolio/.env
ExecStart=/usr/bin/node main.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now ghostfolio
echo "$RELEASE" >/opt/ghostfolio_version.txt
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
npm cache clean --force
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
