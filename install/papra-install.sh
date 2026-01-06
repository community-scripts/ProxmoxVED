#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/papra-hq/papra

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
    build-essential \
    tesseract-ocr \
    tesseract-ocr-all
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

RELEASE=$(curl -fsSL https://api.github.com/repos/papra-hq/papra/releases | grep -oP '"tag_name":\s*"\K@papra/docker@[^"]+' | head -n1)
fetch_and_deploy_gh_release "papra" "papra-hq/papra" "tarball" "${RELEASE}" "/opt/papra"

msg_info "Setup Papra"
cd /opt/papra
export COREPACK_ENABLE_NETWORK=1
$STD corepack enable
$STD corepack prepare pnpm@10.19.0 --activate
$STD pnpm install --frozen-lockfile
$STD pnpm --filter "@papra/app-client..." run build
$STD pnpm --filter "@papra/app-server..." run build
msg_ok "Set up Papra"

msg_info "Configuring Papra"
CONTAINER_IP=$(hostname -I | awk '{print $1}')
BETTER_AUTH_SECRET=$(openssl rand -hex 32)

mkdir -p /opt/papra/app-data/db
mkdir -p /opt/papra/app-data/documents

cat >/opt/papra/.env <<EOF
NODE_ENV=production
SERVER_SERVE_PUBLIC_DIR=true
PORT=1221

# Database Configuration
DATABASE_URL=file:./app-data/db/db.sqlite

# Storage Configuration
DOCUMENT_STORAGE_FILESYSTEM_ROOT=./app-data/documents
PAPRA_CONFIG_DIR=./app-data

# Authentication
BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}
BETTER_AUTH_TELEMETRY=0

# Application Configuration
CLIENT_BASE_URL=http://${CONTAINER_IP}:1221

# Email Configuration (dry-run mode)
EMAILS_DRY_RUN=true

# Ingestion Folder
INGESTION_FOLDER_ROOT=./ingestion
EOF

mkdir -p /opt/papra/ingestion
chown -R root:root /opt/papra
msg_ok "Configured Papra"

msg_info "Creating Papra Service"
cat >/etc/systemd/system/papra.service <<EOF
[Unit]
Description=Papra Document Management
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/papra/apps/papra-server
EnvironmentFile=/opt/papra/.env
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStartPre=/usr/bin/corepack pnpm --silent run migration:apply
ExecStart=/usr/bin/corepack pnpm --silent run start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now papra
echo "${RELEASE}" >/opt/Papra_version.txt
msg_ok "Created and Started Papra Service"

motd_ssh
customize
cleanup_lxc
