#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ente-io/ente

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  libsodium23 libsodium-dev pkg-config caddy
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
setup_go
NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
fetch_and_deploy_gh_release "ente" "ente-io/ente" "tarball" "latest" "/opt/ente"

msg_info "Setting up PostgreSQL"
DB_NAME="ente_db"
DB_USER="ente"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
{
  echo "Ente Credentials"
  echo "Database Name: $DB_NAME"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
} >>~/ente.creds
msg_ok "Set up PostgreSQL"

msg_info "Building Museum (server)"
cd /opt/ente/server
$STD corepack enable
$STD go mod tidy
$STD go build cmd/museum/main.go
cp config/example.yaml museum.yaml
msg_ok "Built Museum"

msg_info "Generating Secrets"
$STD go run tools/gen-random-keys/main.go >secrets.txt
msg_ok "Generated Secrets"

msg_info "Creating Museum Service"
cat <<EOF >/etc/systemd/system/ente-museum.service
[Unit]
Description=Ente Museum Server
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/ente/server
ExecStart=/opt/ente/server/main
Restart=always
Environment="DATABASE_URL=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME"

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ente-museum
msg_ok "Created Museum Service"

msg_info "Building Web Applications"
cd /opt/ente/web
$STD yarn install
export NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080
export NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT=http://localhost:3002
$STD yarn build
$STD yarn build:accounts
$STD yarn build:auth
$STD yarn build:cast
mkdir -p /var/www/ente/apps
cp -r apps/photos/out /var/www/ente/apps/photos
cp -r apps/accounts/out /var/www/ente/apps/accounts
cp -r apps/auth/out /var/www/ente/apps/auth
cp -r apps/cast/out /var/www/ente/apps/cast
msg_ok "Built Web Applications"

msg_info "Configuring Caddy"
cat <<EOF >/etc/caddy/Caddyfile
:3000 {
    root * /var/www/ente/apps/photos
    file_server
    try_files {path} {path}.html /index.html
}
:3001 {
    root * /var/www/ente/apps/accounts
    file_server
    try_files {path} {path}.html /index.html
}
:3002 {
    root * /var/www/ente/apps/photos
    file_server
    try_files {path} {path}.html /index.html
}
:3003 {
    root * /var/www/ente/apps/auth
    file_server
    try_files {path} {path}.html /index.html
}
:3004 {
    root * /var/www/ente/apps/cast
    file_server
    try_files {path} {path}.html /index.html
}
EOF
systemctl reload caddy
msg_ok "Configured Caddy"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
