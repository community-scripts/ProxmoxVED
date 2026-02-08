#!/usr/bin/env bash
# Kener install script for ProxmoxVE container
# Copyright (c) 2021-2026 community-scripts ORG
# Author: danynocz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://kener.ing

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing base dependencies"
$STD apt update
$STD apt install -y \
  git \
  curl \
  ca-certificates \
  openssl \
  sqlite3 \
  build-essential
msg_ok "Base dependencies installed"

msg_info "Installing Node.js 20"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -s -- -q >/tmp/nodesource.log 2>&1
$STD apt install -y nodejs >>/tmp/nodesource.log 2>&1
msg_ok "Node.js installed"

msg_info "Verifying Node.js & npm"
node -v >/dev/null 2>&1
npm -v >/dev/null 2>&1
msg_ok "Node.js & npm verified"

msg_info "Fetching Kener from GitHub"
fetch_and_deploy_gh_release "kener" "rajnandan1/kener" "tarball" "latest" "/opt/kener"
msg_ok "Kener fetched"
msg_ok "Repository cloned"

msg_info "Installing Node dependencies"
$STD npm install >/tmp/kener_npm.log 2>&1
msg_ok "Dependencies installed"

msg_info "Creating .env file"
SERVER_IP="$(hostname -I | awk '{print $1}')"

cat <<EOF >/opt/kener/.env
PORT=3000
ORIGIN=http://${SERVER_IP}:3000
KENER_SECRET_KEY=$(openssl rand -hex 32)
EOF
msg_ok ".env file created"

msg_info "Preparing SQLite database"
$STD npm exec knex migrate:latest >/tmp/kener_db.log 2>&1
$STD npm exec knex seed:run >>/tmp/kener_db.log 2>&1
msg_ok "Database initialized"

msg_info "Creating systemd service"
cat <<EOF >/etc/systemd/system/kener.service
[Unit]
Description=Kener Status Page
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/kener
ExecStart=/usr/bin/npm exec vite dev -- --host 0.0.0.0 --port 3000
Restart=always
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reexec
$STD systemctl daemon-reload
$STD systemctl enable kener
$STD systemctl start kener
msg_ok "Kener service started"

motd_ssh
customize
cleanup_lxc
