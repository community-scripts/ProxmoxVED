#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Kanba-co/kanba

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" NODE_MODULE="npx" setup_nodejs
fetch_and_deploy_gh_release "kanba" "Kanba-co/kanba" "tarball" "latest" "/opt/kanba"
POSTGRES_VERSION="16" setup_postgresql

msg_info "Set up PostgreSQL Database"
DB_NAME=kanba_db
DB_USER=kanba_usr
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
DB_URL="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
{
  echo "Kanba-Credentials"
  echo "Kanba Database Name: $DB_NAME"
  echo "Kanba Database User: $DB_USER"
  echo "Kanba Database Password: $DB_PASS"
} >>~/kanba.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Preparing .env.local"
cd /opt/kanba
cp .env.example .env.local
sed -i "s|^DATABASE_PROVIDER=.*|DATABASE_PROVIDER=postgresql|" .env.local
sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" .env.local
sed -i "s|^NEXT_PUBLIC_SITE_URL=.*|NEXT_PUBLIC_SITE_URL=http://localhost:3000|" .env.local
sed -i "s|^NEXTAUTH_URL=.*|NEXTAUTH_URL=http://localhost:3000|" .env.local
sed -i "s|^NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=$(openssl rand -hex 32)|" .env.local
msg_ok "Prepared .env.local"

msg_info "Installing Kanba"
$STD npm install
$STD npx prisma generate
$STD npx prisma migrate deploy
$STD npm run build
msg_ok "Installed Kanba"

msg_info "Creating systemd Service"
cat <<EOF >/etc/systemd/system/kanba.service
[Unit]
Description=Kanba - Lightweight Trello Alternative
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/kanba
EnvironmentFile=/opt/kanba/.env.local
ExecStart=/usr/bin/npx next start -p 3000
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now kanba
msg_ok "Created systemd Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
