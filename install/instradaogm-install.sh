#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rdeangel
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rdeangel/InstradaOGM

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y sqlite3
msg_ok "Installed Dependencies"

NODE_VERSION="23" setup_nodejs
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "instradaogm" "rdeangel/InstradaOGM" "prebuild" "latest" "/opt/instradaogm" "instradaogm-sqlite-v*-amd64.tar.gz"

import_local_ip

msg_info "Installing InstradaOGM"
cd /opt/instradaogm || exit
NEXTAUTH_SECRET=$(openssl rand -base64 32)
BACKUP_SECRET=$(openssl rand -hex 32)
export DATABASE_URL="file:/opt/instradaogm/data/db/instradaogm.db"
cat > .env <<EOF
# --- Required OPNsense Configuration ---
OPNSENSE_URL=
OPNSENSE_API_KEY=
OPNSENSE_API_SECRET=
SKIP_SSL_VERIFICATION=false

# --- Database (SQLite) ---
DATABASE_URL="$DATABASE_URL"

# --- Security & Auth ---
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
BACKUP_ENCRYPTION_SECRET_KEY=$BACKUP_SECRET
NEXTAUTH_URL="http://${LOCAL_IP}:3000"
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

export NODE_OPTIONS='--max-old-space-size=512'
$STD npm run setup-dirs
$STD npm run db:init
$STD npm run db:seed
unset NODE_OPTIONS

msg_ok "Installed InstradaOGM"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/instradaogm.service
[Unit]
Description=InstradaOGM Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/instradaogm
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reload
$STD systemctl enable --now instradaogm
msg_ok "Created and Started Service"

motd_ssh
customize
cleanup_lxc
