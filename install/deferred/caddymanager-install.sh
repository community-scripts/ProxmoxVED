#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/caddymanager/caddymanager

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y caddy
msg_ok "Installed Dependencies"

NODE_VERSION=22 setup_nodejs
fetch_and_deploy_gh_release "caddymanager" "caddymanager/caddymanager" "tarball"
systemctl stop caddy
systemctl disable -q caddy

msg_info "Configuring CaddyManager"
SECRET_JWT=$(openssl rand -hex 32)
cd /opt/caddymanager/backend
$STD npm install
cd /opt/caddymanager/frontend
$STD npm install
$STD npm run build

cat <<EOF >/opt/caddymanager/caddymanager.env
PORT=3000
APP_NAME=Caddy Manager
DB_ENGINE=sqlite
SQLITE_DB_PATH=/opt/caddymanager/caddymanager.sqlite
CORS_ORIGIN=${LOCAL_IP}:80
LOG_LEVEL=debug
CADDY_SANDBOX_URL=http://localhost:2019
PING_INTERVAL=30000
PING_TIMEOUT=2000
AUDIT_LOG_MAX_SIZE_MB=100
AUDIT_LOG_RETENTION_DAYS=90
METRICS_HISTORY_MAX=1000
JWT_SECRET=${SECRET_JWT}
JWT_EXPIRATION=24h
EOF
sed -i 's|/usr/share/caddy|/opt/caddymanager/frontend/dist|g' /opt/caddymanager/frontend/Caddyfile
msg_ok "Configured CaddyManager"

msg_info "Creating services"
cat <<EOF >/etc/systemd/system/caddymanager-backend.service
[Unit]
Description=Caddymanager Backend Service
After=network.target

[Service]
WorkingDirectory=/opt/caddymanager/backend
ExecStart=/usr/bin/npm start
Restart=always
EnvironmentFile=/opt/caddymanager/caddymanager.env

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/caddymanager-frontend.service
[Unit]
Description=Caddymanager Frontend Service
After=network.target caddymanager-backend.service
Requires=caddymanager-backend.service

[Service]
WorkingDirectory=/opt/caddymanager/frontend
ExecStart=/usr/bin/caddy run --config Caddyfile
Restart=always
EnvironmentFile=/opt/caddymanager/caddymanager.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now caddymanager-backend
systemctl enable -q --now caddymanager-frontend
msg_ok "Created services"

motd_ssh
customize
cleanup_lxc
