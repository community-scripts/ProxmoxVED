#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://hanko.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_yq
PG_VERSION="16" setup_postgresql
NODE_VERSION=22 NODE_MODULE="yarn@latest,npm@latest" setup_nodejs

msg_info "Setting up PostgreSQL Database"
DB_NAME=hanko
DB_USER=hanko
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
APP_SECRET=$(openssl rand -base64 32)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "Hanko-Credentials"
  echo "Hanko Database User: $DB_USER"
  echo "Hanko Database Password: $DB_PASS"
  echo "Hanko Database Name: $DB_NAME"
} >>~/hanko.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Setup Hanko"
fetch_and_deploy_gh_release "hanko" "teamhanko/hanko" "prebuild" "latest" "/opt/hanko" "hanko_Linux_x86_64.tar.gz"
curl -fsSL https://raw.githubusercontent.com/teamhanko/hanko/refs/heads/main/backend/config/config.yaml -o /opt/hanko/config.yaml
env DB_USER="$DB_USER" DB_PASS="$DB_PASS" APP_SECRET="$APP_SECRET" \
  yq eval '
  .database.user = strenv(DB_USER) |
  .database.password = strenv(DB_PASS) |
  .database.host = "localhost" |
  .database.port = "5432" |
  .database.dialect = "postgres" |
  .app.secret = strenv(APP_SECRET)
' -i /opt/hanko/config.yaml
$STD /opt/hanko/hanko --config /opt/hanko/config.yaml migrate up
yarn add @teamhanko/hanko-elements
msg_ok "Setup Hanko"

msg_info "Setup Service"
cat <<EOF >/etc/systemd/system/hanko.service
[Unit]
Description=Hanko Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/hanko/hanko serve all --config /opt/hanko/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now hanko
msg_ok "Service Setup"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
