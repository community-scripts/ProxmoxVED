#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/CrazyWolf13/domain-locker

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="17" setup_postgresql
PG_DB_NAME="domainlocker" PG_DB_USER="domainlocker" setup_postgresql_db
NODE_VERSION="22" setup_nodejs


$STD apt install -y git
git clone https://github.com/Lissy93/domain-locker.git /opt/domain-locker
# fetch_and_deploy_gh_release "domain-locker" "Lissy93/domain-locker"

msg_info "Building Domain-Locker"
cd /opt/domain-locker
# $STD npm install --legacy-peer-deps
npm install
export NODE_OPTIONS="--max-old-space-size=8192"
cat <<EOF >/opt/domain-locker.env
# Database connection
DL_PG_HOST=localhost
DL_PG_PORT=5432
DL_PG_USER=$PG_DB_USER
DL_PG_PASSWORD=$PG_DB_PASS
DL_PG_NAME=$PG_DB_NAME

# Build + Runtime
DL_ENV_TYPE=selfHosted
NITRO_PRESET=node_server
NODE_ENV=production
EOF
set -a
source /opt/domain-locker.env
set +a
npm run build
msg_info "Built Domain-Locker"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/domain-locker.service
[Unit]
Description=Domain-Locker Service
After=network.target

[Service]
EnvironmentFile=/opt/domain-locker.env
WorkingDirectory=/opt/domain-locker
ExecStart=/opt/domain-locker/start.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl start --now -q domain-locker
msg_info "Created Service"

motd_ssh
customize
cleanup_lxc
