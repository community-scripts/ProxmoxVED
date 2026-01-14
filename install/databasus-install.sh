#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/databasus/databasus

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
PG_DB_NAME="databasus" PG_DB_USER="databasus" setup_postgresql_db
setup_go
NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "databasus" "databasus/databasus" "tarball" "latest" "/opt/databasus"

msg_info "Building Databasus (Patience)"
cd /opt/databasus/frontend
$STD npm ci
$STD npm run build
cd /opt/databasus/backend
$STD go mod tidy
$STD go mod download
$STD go install github.com/swaggo/swag/cmd/swag@latest
$STD /root/go/bin/swag init -g cmd/main.go -o swagger
$STD env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o databasus ./cmd/main.go
mv /opt/databasus/backend/databasus /opt/databasus/databasus
mkdir -p /opt/databasus_data/{data,backups,logs}
mkdir -p /databasus-data/temp
mkdir -p /opt/databasus/ui/build
cp -r /opt/databasus/frontend/dist/* /opt/databasus/ui/build/
cp -r /opt/databasus/backend/migrations /opt/databasus/
chown -R postgres:postgres /opt/databasus
chown -R postgres:postgres /opt/databasus_data
chown -R postgres:postgres /databasus-data
msg_ok "Built Databasus"

msg_info "Configuring Databasus"
ADMIN_PASS=$(openssl rand -base64 12)
JWT_SECRET=$(openssl rand -hex 32)

# Create PostgreSQL version symlinks for compatibility
for v in 12 13 14 15 16 18; do
  ln -sf /usr/lib/postgresql/17 /usr/lib/postgresql/$v
done

# Install goose for migrations
$STD go install github.com/pressly/goose/v3/cmd/goose@latest
ln -sf /root/go/bin/goose /usr/local/bin/goose

cat <<EOF >/opt/databasus/.env
# Environment
ENV_MODE=production

# Server
SERVER_PORT=4005
SERVER_HOST=0.0.0.0

# Database (Internal PostgreSQL for app data)
DATABASE_DSN=host=localhost user=${PG_DB_USER} password=${PG_DB_PASS} dbname=${PG_DB_NAME} port=5432 sslmode=disable
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}?sslmode=disable

# Migrations
GOOSE_DRIVER=postgres
GOOSE_DBSTRING=postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}?sslmode=disable
GOOSE_MIGRATION_DIR=/opt/databasus/migrations

# Security
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Admin User
ADMIN_EMAIL=admin@localhost
ADMIN_PASSWORD=${ADMIN_PASS}

# Paths
DATA_DIR=/opt/databasus_data/data
BACKUP_DIR=/opt/databasus_data/backups
LOG_DIR=/opt/databasus_data/logs

# PostgreSQL Tools (for creating backups)
PG_DUMP_PATH=/usr/lib/postgresql/17/bin/pg_dump
PG_RESTORE_PATH=/usr/lib/postgresql/17/bin/pg_restore
PSQL_PATH=/usr/lib/postgresql/17/bin/psql
EOF
chown postgres:postgres /opt/databasus/.env
chmod 600 /opt/databasus/.env
msg_ok "Configured Databasus"

msg_info "Creating Databasus Service"
cat <<EOF >/etc/systemd/system/databasus.service
[Unit]
Description=Databasus - PostgreSQL Backup Management
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=postgres
Group=postgres
WorkingDirectory=/opt/databasus
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=/opt/databasus/.env
ExecStart=/opt/databasus/databasus
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl daemon-reload
$STD systemctl enable -q --now databasus
msg_ok "Created Databasus Service"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/databasus
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
