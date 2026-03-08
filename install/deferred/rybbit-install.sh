#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
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

setup_clickhouse
PG_VERSION=17 setup_postgresql
NODE_VERSION="24" NODE_MODULE="next" setup_nodejs
PG_DB_NAME="rybbit_db" PG_DB_USER="rybbit" setup_postgresql_db

fetch_and_deploy_gh_release "rybbit" "rybbit-io/rybbit" "tarball" "latest" "/opt/rybbit"

msg_info "Building Rybbit Shared Module"
cd /opt/rybbit/shared
$STD npm install
$STD npm run build
msg_ok "Built Shared Module"

msg_info "Building Rybbit Server"
cd /opt/rybbit/server
$STD npm ci
$STD npm run build
msg_ok "Built Server"

msg_info "Building Rybbit Client"
cd /opt/rybbit/client
NEXT_PUBLIC_BACKEND_URL="http://localhost:3001" \
  NEXT_PUBLIC_DISABLE_SIGNUP="false" \
  $STD npm ci --legacy-peer-deps
$STD npm run build
msg_ok "Built Client"

msg_info "Configuring Rybbit"
CONTAINER_IP=$(hostname -I | awk '{print $1}')
BETTER_AUTH_SECRET=$(openssl rand -hex 32)

cat >/opt/rybbit/.env <<EOF
# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=$PG_DB_NAME
POSTGRES_USER=$PG_DB_USER
POSTGRES_PASSWORD=$PG_DB_PASS

CLICKHOUSE_HOST=http://localhost:8123
CLICKHOUSE_DB=analytics
CLICKHOUSE_PASSWORD=

# Application Configuration
NODE_ENV=production
BASE_URL=http://${CONTAINER_IP}:3002
BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}
DISABLE_SIGNUP=false
DISABLE_TELEMETRY=true
MAPBOX_TOKEN=
EOF
msg_ok "Configured Rybbit"

msg_info "Creating Rybbit Services"
cat >/etc/systemd/system/rybbit-server.service <<EOF
[Unit]
Description=Rybbit Server
After=network.target postgresql.service clickhouse-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rybbit/server
EnvironmentFile=/opt/rybbit/.env
ExecStart=/usr/bin/node /opt/rybbit/server/dist/index.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/rybbit-client.service <<EOF
[Unit]
Description=Rybbit Client
After=network.target rybbit-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rybbit/client
Environment="NODE_ENV=production"
Environment="NEXT_PUBLIC_BACKEND_URL=http://${CONTAINER_IP}:3001"
Environment="NEXT_PUBLIC_DISABLE_SIGNUP=false"
Environment="PORT=3002"
Environment="HOSTNAME=0.0.0.0"
ExecStart=/usr/bin/node /opt/rybbit/client/.next/standalone/server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now rybbit-server.service
systemctl enable -q --now rybbit-client.service
msg_ok "Created and Started Rybbit Services"

motd_ssh
customize
cleanup_lxc
