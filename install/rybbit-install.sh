#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rybbit-io/rybbit

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  caddy \
  apt-transport-https \
  ca-certificates
msg_ok "Installed Dependencies"

setup_clickhouse
PG_VERSION=17 setup_postgresql
NODE_VERSION="24" NODE_MODULE="next" setup_nodejs
PG_DB_NAME="rybbit_db" PG_DB_USER="rybbit" setup_postgresql_db

fetch_and_deploy_gh_release "rybbit" "rybbit-io/rybbit" "tarball" "latest" "/opt/rybbit"

msg_info "Installing Rybbit"
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
sed -i "s|^POSTGRES_DB=.*|POSTGRES_DB=$PG_DB_NAME|g" /opt/rybbit/.env
sed -i "s|^POSTGRES_USER=.*|POSTGRES_USER=$PG_DB_USER|g" /opt/rybbit/.env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$PG_DB_PASS|g" /opt/rybbit/.env
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
cleanup_lxc
