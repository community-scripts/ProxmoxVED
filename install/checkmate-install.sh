#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bluewave-labs/Checkmate

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  openssl
msg_ok "Installed Dependencies"

MONGO_VERSION="8.0" setup_mongodb
NODE_VERSION="22" setup_nodejs
fetch_and_deploy_gh_release "checkmate" "bluewave-labs/Checkmate"

msg_info "Installing Checkmate Server"
cd /opt/checkmate/server
$STD npm install
msg_ok "Installed Checkmate Server"

msg_info "Installing Checkmate Client"
cd /opt/checkmate/client
$STD npm install
$STD npm run build
msg_ok "Installed Checkmate Client"

msg_info "Configuring Checkmate"
JWT_SECRET="$(openssl rand -hex 32)"
cat <<EOF >/opt/checkmate/server/.env
CLIENT_HOST="http://${LOCAL_IP}:5173"
JWT_SECRET="${JWT_SECRET}"
DB_CONNECTION_STRING="mongodb://localhost:27017/checkmate_db"
TOKEN_TTL="99d"
ORIGIN="${LOCAL_IP}"
LOG_LEVEL="info"
EOF

cat <<EOF >/opt/checkmate/client/.env
VITE_APP_API_BASE_URL="http://${LOCAL_IP}:52345/api/v1"
VITE_APP_LOG_LEVEL="warn"
EOF
msg_ok "Configured Checkmate"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/checkmate-server.service
[Unit]
Description=Checkmate Server
After=network.target mongod.service

[Service]
Type=simple
WorkingDirectory=/opt/checkmate/server
EnvironmentFile=/opt/checkmate/server/.env
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/checkmate-client.service
[Unit]
Description=Checkmate Client
After=network.target checkmate-server.service

[Service]
Type=simple
WorkingDirectory=/opt/checkmate/client
EnvironmentFile=/opt/checkmate/client/.env
ExecStart=/usr/bin/npm run preview -- --host 0.0.0.0 --port 5173
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now checkmate-server checkmate-client
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
