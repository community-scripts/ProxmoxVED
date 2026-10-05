#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/FalkorDB/FalkorDB

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Redis"
setup_deb822_repo \
  "redis" \
  "https://packages.redis.io/gpg" \
  "https://packages.redis.io/deb" \
  "trixie"
$STD apt install -y redis-server
msg_ok "Installed Redis"

fetch_and_deploy_gh_release "falkordb" "FalkorDB/FalkorDB" "singlefile" "latest" "/opt/falkordb" "falkordb-$(arch_resolve "x64" "arm64v8").so"

msg_info "Configuring FalkorDB"
mkdir -p /var/lib/FalkorDB/import
cat <<EOF >/etc/redis/falkordb.conf
bind 0.0.0.0 -::*
requirepass $(random_password)
appendonly yes
loadmodule /opt/falkordb/falkordb MAX_QUEUED_QUERIES 25 TIMEOUT 1000 RESULTSET_SIZE 10000
EOF
chown redis:redis /etc/redis/falkordb.conf
chmod 640 /etc/redis/falkordb.conf
# The official FalkorDB image loads no other module; Redis 8 enables its bundled ones by default
sed -i 's|^loadmodule /usr/lib/redis/modules/|# &|' /etc/redis/redis.conf
cat <<EOF >>/etc/redis/redis.conf

include /etc/redis/falkordb.conf
EOF
systemctl restart redis-server
msg_ok "Configured FalkorDB"

NODE_VERSION="24" setup_nodejs
fetch_and_deploy_gh_release "falkordb-browser" "FalkorDB/falkordb-browser" "tarball"

msg_info "Building FalkorDB Browser"
cd /opt/falkordb-browser
$STD npm ci
NEXT_TELEMETRY_DISABLED=1 $STD npm run build
cp -r .next/static .next/standalone/.next/
cp -r public .next/standalone/
msg_ok "Built FalkorDB Browser"

msg_info "Configuring FalkorDB Browser"
mkdir -p /opt/falkordb-browser_data
cat <<EOF >/opt/falkordb-browser_data/.env
NODE_ENV=production
NEXT_TELEMETRY_DISABLED=1
HOSTNAME=0.0.0.0
PORT=3000
NEXTAUTH_URL=http://${LOCAL_IP}:3000
AUTH_SECRET=$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
API_TOKEN_STORAGE_PATH=/opt/falkordb-browser_data/api_tokens.json
CSV_STORAGE=local
CSV_LOCAL_TEMP_DIR=/var/lib/FalkorDB/import
CSV_LOCAL_LOAD_URI_MODE=file
EOF
chmod 600 /opt/falkordb-browser_data/.env
msg_ok "Configured FalkorDB Browser"

msg_info "Creating FalkorDB Browser Service"
cat <<EOF >/etc/systemd/system/falkordb-browser.service
[Unit]
Description=FalkorDB Browser
After=network.target redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/falkordb-browser/.next/standalone
EnvironmentFile=/opt/falkordb-browser_data/.env
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now falkordb-browser
msg_ok "Created FalkorDB Browser Service"

motd_ssh
customize
cleanup_lxc
