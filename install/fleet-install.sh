#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fleetdm/fleet

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_mariadb
MARIADB_DB_NAME="fleet" MARIADB_DB_USER="fleet" setup_mariadb_db

fetch_and_deploy_gh_release "fleet" "fleetdm/fleet" "prebuild" "latest" "/opt/fleet" "fleet_v*_linux.tar.gz"

msg_info "Configuring Application"
chmod +x /opt/fleet/fleet
JWT_KEY=$(openssl rand -base64 32)
cat <<EOF >/opt/fleet/.env
FLEET_MYSQL_ADDRESS=127.0.0.1:3306
FLEET_MYSQL_DATABASE=fleet
FLEET_MYSQL_USERNAME=fleet
FLEET_MYSQL_PASSWORD=${MARIADB_DB_PASS}
FLEET_SERVER_ADDRESS=0.0.0.0:8080
FLEET_SERVER_TLS=false
FLEET_AUTH_JWT_KEY=${JWT_KEY}
FLEET_LOGGING_JSON=true
EOF
msg_ok "Configured Application"

msg_info "Running Database Migrations"
set -a && source /opt/fleet/.env && set +a
$STD /opt/fleet/fleet prepare db
msg_ok "Ran Database Migrations"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/fleet.service
[Unit]
Description=Fleet
After=network.target mariadb.service
Requires=mariadb.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fleet
EnvironmentFile=/opt/fleet/.env
ExecStart=/opt/fleet/fleet serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now fleet
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
