#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
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
$STD go mod tidy
$STD go mod download
$STD go install github.com/swaggo/swag/cmd/swag@latest
$STD /root/go/bin/swag init -g cmd/main.go -o swagger
$STD env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o postgresus ./cmd/main.go
mv /opt/postgresus/backend/postgresus /opt/postgresus/postgresus
mkdir -p /opt/postgresus_data/{data,backups,logs}
mkdir -p /postgresus-data/temp
mkdir -p /opt/postgresus/ui/build
cp -r /opt/postgresus/frontend/dist/* /opt/postgresus/ui/build/
cp -r /opt/postgresus/backend/migrations /opt/postgresus/
chown -R postgres:postgres /opt/postgresus
chown -R postgres:postgres /opt/postgresus_data
chown -R postgres:postgres /postgresus-data
msg_ok "Built Postgresus"

msg_info "Configuring Postgresus"
ADMIN_PASS=$(openssl rand -base64 12)
JWT_SECRET=$(openssl rand -hex 32)

# Create PostgreSQL version symlinks for compatibility
for v in 12 13 14 15 16 18; do
  ln -sf /usr/lib/postgresql/17 /usr/lib/postgresql/$v
done

# Install goose for migrations
$STD go install github.com/pressly/goose/v3/cmd/goose@latest
ln -sf /root/go/bin/goose /usr/local/bin/goose

cat <<EOF >/opt/postgresus/.env
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
GOOSE_MIGRATION_DIR=/opt/postgresus/migrations

# Security
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Admin User
ADMIN_EMAIL=admin@localhost
ADMIN_PASSWORD=${ADMIN_PASS}

# Paths
DATA_DIR=/opt/postgresus_data/data
BACKUP_DIR=/opt/postgresus_data/backups
LOG_DIR=/opt/postgresus_data/logs

# PostgreSQL Tools (for creating backups)
PG_DUMP_PATH=/usr/lib/postgresql/17/bin/pg_dump
PG_RESTORE_PATH=/usr/lib/postgresql/17/bin/pg_restore
PSQL_PATH=/usr/lib/postgresql/17/bin/psql
EOF
chown postgres:postgres /opt/postgresus/.env
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
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=/opt/postgresus/.env
ExecStart=/opt/postgresus/postgresus
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl daemon-reload
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
