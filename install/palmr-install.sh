#!/usr/bin/env bash

# Copyright (c) 2025 Community Scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kyantech/Palmr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y yq
msg_ok "Installed dependencies"

NODE_VERSION="20" setup_nodejs

fetch_and_deploy_gh_release "Palmr" "kyantech/Palmr" "tarball" "latest" "/opt/palmr"
msg_info "Configuring palmr backend"
PALMR_DIR="/opt/palmr_data"
mkdir -p "$PALMR_DIR"
PALMR_DB="${PALMR_DIR}/palmr.db"
PALMR_KEY="$(openssl rand -hex 32)"
cd /opt/palmr/apps/server
sed -e 's/_ENCRYPTION=true/_ENCRYPTION=false/' \
  -e '/^# ENC/s/# //' \
  -e "s/ENCRYPTION_KEY=.*$/ENCRYPTION_KEY=$PALMR_KEY/" \
  -e "s|file:.*$|file:$PALMR_DB\"|" \
  .env.example >./.env
sed -i "s|/app/server|$PALMR_DIR|" ./src/config/directories.config.ts
$STD pnpm install
$STD pnpm dlx prisma generate
$STD pnpm dlx prisma migrate deploy
$STD pnpm dlx prisma db push # This was missing from the docs
$STD pnpm db:seed
$STD pnpm build
msg_ok "Configured palmr backend"

msg_info "Configuring palmr frontend"
cd /opt/palmr/apps/web
mv ./.env.example ./.env
export NODE_ENV=production
export NEXT_TELEMETRY_DISABLED=1
$STD pnpm install
$STD pnpm build
msg_ok "Configured palmr frontend"

msg_info "Creating service files"
cat <<EOF >/etc/systemd/system/palmr-backend.service
[Unit]
Description=palmr Backend Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/palmr/apps/server
ExecStart=/usr/bin/pnpm start

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/palmr-frontend.service
[Unit]
Description=palmr Frontend Service
After=network.target palmr-backend.service

[Service]
Type=simple
WorkingDirectory=/opt/palmr/apps/web
ExecStart=/usr/bin/pnpm start

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now palmr-backend palmr-frontend
msg_ok "Created services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
