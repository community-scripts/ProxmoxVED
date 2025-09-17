#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rybbit-io/rybbit

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
init_error_traps
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    caddy \
    apt-transport-https \
    ca-certificates
msg_ok "Installed Dependencies"

setup_clickhouse
PG_VERSION=17 setup_postgresql
NODE_VERSION="20" NODE_MODULE="next" setup_nodejs

#sed -i 's|<default_profile>default</default_profile>|<default_profile>read_only</default_profile>|' /etc/clickhouse-server/users.xml
#sed -i 's|<default_password></default_password>|<default_password>DISABLED</default_password>|' /etc/clickhouse-server/users.xml

msg_info "Setting up PostgreSQL Database"
DB_NAME=rybbit_db
DB_USER=rybbit
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
    echo "Rybbit-Credentials"
    echo "Rybbit Database User: $DB_USER"
    echo "Rybbit Database Password: $DB_PASS"
    echo "Rybbit Database Name: $DB_NAME"
} >>~/rybbit.creds
msg_ok "Set up PostgreSQL Database"

fetch_and_deploy_gh_release "rybbit" "rybbit-io/rybbit" "tarball" "latest" "/opt/rybbit"

cd /opt/rybbit/shared
npm install
npm run build

cd /opt/rybbit/server
npm ci
npm run build

cd /opt/rybbit/client
npm ci --legacy-peer-deps
npm run build

mv /opt/rybbit/.env.example /opt/rybbit/.env
sed -i "s|^POSTGRES_DB=.*|POSTGRES_DB=$DB_NAME|g" /opt/rybbit/.env
sed -i "s|^POSTGRES_USER=.*|POSTGRES_USER=$DB_USER|g" /opt/rybbit/.env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$DB_PASS|g" /opt/rybbit/.env
sed -i "s|^DOMAIN_NAME=.*|DOMAIN_NAME=localhost|g" /opt/rybbit/.env
sed -i "s|^BASE_URL=.*|BASE_URL=\"http://localhost\"|g" /opt/rybbit/.env
msg_ok "Rybbit Installed"

msg_info "Setting up Caddy"
mkdir -p /etc/caddy
cp /opt/rybbit/Caddyfile /etc/caddy/Caddyfile
systemctl enable -q --now caddy
msg_ok "Caddy Setup"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
