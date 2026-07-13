#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Åsbjørn Hansen (asbjornhansen)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://taskosaur.com/ | Github: https://github.com/Taskosaur/Taskosaur

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y redis-server
systemctl enable -q --now redis-server
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="taskosaur" PG_DB_USER="taskosaur" setup_postgresql_db

fetch_and_deploy_gh_tag "taskosaur" "Taskosaur/Taskosaur"

msg_info "Setting up Taskosaur"
mkdir -p /opt/taskosaur/uploads
cat <<EOF >/opt/taskosaur/.env
NODE_ENV=production
HOST=0.0.0.0
PORT=3000
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d
ENCRYPTION_KEY=$(openssl rand -hex 32)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0
FRONTEND_URL=http://${LOCAL_IP}:3000
CORS_ORIGIN=http://${LOCAL_IP}:3000
CORS_ORIGINS=http://${LOCAL_IP}:3000
NEXT_PUBLIC_API_BASE_URL=http://${LOCAL_IP}:3000/api
UPLOAD_DEST=/opt/taskosaur/uploads
UPLOAD_DIR=/opt/taskosaur/uploads
MAX_FILE_SIZE=10485760
MAX_EDITOR_IMAGE_SIZE=5242880
ALLOWED_IMAGE_TYPES=image/jpeg,image/png,image/gif,image/webp
EDITOR_IMAGE_UPLOAD_FOLDER=editor-images
MAX_CONCURRENT_JOBS=5
JOB_RETRY_ATTEMPTS=3
EOF
cd /opt/taskosaur || exit
set -a
source /opt/taskosaur/.env
set +a
export NODE_OPTIONS="--max-old-space-size=3072"
HUSKY=0 $STD npm install --include=dev
$STD npm run build:dist
cd /opt/taskosaur/dist || exit
$STD npm run prisma:generate
$STD npm run prisma:migrate:deploy
rm -rf /opt/taskosaur/node_modules
msg_ok "Set up Taskosaur"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/taskosaur.service
[Unit]
Description=Taskosaur Service
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/taskosaur/dist
EnvironmentFile=/opt/taskosaur/.env
ExecStart=/usr/bin/node /opt/taskosaur/dist/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now taskosaur
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
