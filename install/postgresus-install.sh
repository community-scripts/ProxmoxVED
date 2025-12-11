#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RostislavDugin/postgresus

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

import_local_ip
PG_VERSION="17" setup_postgresql
PG_DB_NAME="postgresus" PG_DB_USER="postgresus" setup_postgresql_db
setup_go
NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "postgresus" "RostislavDugin/postgresus" "tarball" "latest" "/opt/postgresus"

msg_info "Building Postgresus (Patience)"
cd /opt/postgresus/frontend
$STD npm ci
$STD npm run build
cd /opt/postgresus/backend
$STD go mod download
$STD go build -o /opt/postgresus/postgresus ./cmd/main.go
mkdir -p /opt/postgresus/{data,backups,logs}
cp -r /opt/postgresus/frontend/dist /opt/postgresus/ui
cp -r /opt/postgresus/backend/migrations /opt/postgresus/
chown -R postgres:postgres /opt/postgresus
msg_ok "Built Postgresus"

msg_info "Configuring Postgresus"
ADMIN_PASS=$(openssl rand -base64 12)
JWT_SECRET=$(openssl rand -hex 32)
cat <<EOF >/opt/postgresus/.env
# Environment
ENV_MODE=production

# Server
SERVER_PORT=4005
SERVER_HOST=0.0.0.0

# Database (Internal PostgreSQL for app data)
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}?sslmode=disable

# Security
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Admin User
ADMIN_EMAIL=admin@localhost
ADMIN_PASSWORD=${ADMIN_PASS}

# Paths
DATA_DIR=/opt/postgresus/data
BACKUP_DIR=/opt/postgresus/backups
LOG_DIR=/opt/postgresus/logs

# PostgreSQL Tools (for creating backups)
PG_DUMP_PATH=/usr/bin/pg_dump
PG_RESTORE_PATH=/usr/bin/pg_restore
PSQL_PATH=/usr/bin/psql
EOF
chmod 600 /opt/postgresus/.env
msg_ok "Configured Postgresus"

msg_info "Creating Postgresus Service"
cat <<EOF >/etc/systemd/system/postgresus.service
[Unit]
Description=Postgresus - PostgreSQL Backup Management
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=postgres
Group=postgres
WorkingDirectory=/opt/postgresus
EnvironmentFile=/opt/postgresus/.env
ExecStart=/opt/postgresus/postgresus
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable -q --now postgresus
msg_ok "Created Postgresus Service"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/postgresus
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:4005;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/postgresus /etc/nginx/sites-enabled/postgresus
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
$STD systemctl enable -q --now nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
