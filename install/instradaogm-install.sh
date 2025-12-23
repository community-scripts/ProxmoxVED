#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rdeangel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rdeangel/InstradaOGM

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="23" NODE_MODULE="pm2" setup_nodejs
fetch_and_deploy_gh_release "instradaogm" "rdeangel/InstradaOGM" "tarball"

ensure_dependencies python3 sqlite3 ca-certificates jq
  
msg_info "Installing InstradaOGM"
cd /opt/instradaogm
$STD npm run db:switch:sqlite
$STD npm install
NEXTAUTH_SECRET=$(openssl rand -base64 32)
BACKUP_SECRET=$(openssl rand -hex 32)
CONTAINER_IP=$(hostname -I | awk '{print $1}')
cat > .env <<EOF
# --- Required OPNsense Configuration ---
OPNSENSE_URL=
OPNSENSE_API_KEY=
OPNSENSE_API_SECRET=
SKIP_SSL_VERIFICATION=false

# --- Database (SQLite) ---
DATABASE_URL="file:/opt/instradaogm/data/db/instrada-ogm.db"

# --- Security & Auth ---
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
BACKUP_ENCRYPTION_SECRET_KEY=$BACKUP_SECRET
NEXTAUTH_URL="http://${CONTAINER_IP}:3000"
ALLOW_HTTP=true

# --- Application Settings ---
PORT=3000
NODE_ENV=production
APP_DEBUG_LEVEL=ERROR
DATA_FOLDER_PATH=data

# --- Local Credentials Login ---
AUTH_ALLOW_LOCAL_LOGIN=true
AUTH_REQUIRE_VERIFIED_EMAIL_LOCAL=false
AUTH_ALLOW_LOCAL_2FA=true
AUTH_PASSWORD_MIN_LENGTH=8

# --- Email Notifications (Optional) ---
AUTH_SMTP_HOST=smtp.example.com
AUTH_SMTP_PORT=25
AUTH_SMTP_USER=
AUTH_SMTP_PASS=
AUTH_SMTP_FROM_EMAIL=InstradaOGM<admin@example.com>
EOF
$STD node scripts/setup-dirs.js
$STD npm run db:init
DATABASE_URL="file:/opt/instradaogm/data/db/instrada-ogm.db" $STD npx tsx prisma/seed.ts
$STD npm run build
msg_ok "Installed InstradaOGM"

msg_info "Starting Service"
$STD pm2 start npm --name "instrada-ogm" -- start
$STD pm2 save
$STD pm2 startup systemd -u root --hp /root
msg_ok "Started Service"

motd_ssh
customize
cleanup_lxc
