#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Majiiin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/johanohly/AirTrail

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  unzip
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Installing Bun"
export BUN_INSTALL="/root/.bun"
curl -fsSL https://bun.com/install | $STD bash
ln -sf /root/.bun/bin/bun /usr/local/bin/bun
ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
msg_ok "Installed Bun"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="airtrail" PG_DB_USER="airtrail" setup_postgresql_db

fetch_and_deploy_gh_release "airtrail" "johanohly/AirTrail" "tarball"

msg_info "Configuring AirTrail"
useradd \
  --system \
  --home-dir /opt/airtrail \
  --shell /usr/sbin/nologin \
  airtrail

mkdir -p \
  /etc/airtrail \
  /var/lib/airtrail/uploads

cat <<EOF_ENV >/etc/airtrail/airtrail.env
NODE_ENV=production
HOST=0.0.0.0
PORT=3000
ORIGIN=http://${LOCAL_IP}:3000
DB_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
UPLOAD_LOCATION=/var/lib/airtrail/uploads
BODY_SIZE_LIMIT=20M
EOF_ENV

chown root:airtrail /etc/airtrail/airtrail.env
chmod 640 /etc/airtrail/airtrail.env
chown -R airtrail:airtrail /var/lib/airtrail
msg_ok "Configured AirTrail"

msg_info "Building AirTrail"
cd /opt/airtrail
$STD bun install --frozen-lockfile
$STD bun run build

rm -rf /opt/airtrail/node_modules
$STD bun install --frozen-lockfile --production
msg_ok "Built AirTrail"

msg_info "Applying Database Migrations"
set -a
source /etc/airtrail/airtrail.env
set +a
$STD node /opt/airtrail/docker/migrate.js
msg_ok "Applied Database Migrations"

msg_info "Creating Service"
cat <<'EOF_SERVICE' >/etc/systemd/system/airtrail.service
[Unit]
Description=AirTrail Flight Tracker
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service

[Service]
Type=simple
User=airtrail
Group=airtrail
WorkingDirectory=/opt/airtrail
EnvironmentFile=/etc/airtrail/airtrail.env
ExecStart=/usr/bin/node /opt/airtrail/build
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl enable -q --now airtrail
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
