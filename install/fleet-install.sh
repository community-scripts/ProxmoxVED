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

msg_info "Setting up Database"
FLEET_DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 13)
$STD mysql -u root <<EOSQL
CREATE DATABASE fleet;
CREATE USER 'fleet'@'localhost' IDENTIFIED BY '${FLEET_DB_PASS}';
GRANT ALL PRIVILEGES ON fleet.* TO 'fleet'@'localhost';
FLUSH PRIVILEGES;
EOSQL
msg_ok "Set up Database"

fetch_and_deploy_gh_release "fleet" "fleetdm/fleet" "prebuild" "latest" "/opt/fleet" "fleet_v*_linux.tar.gz"

msg_info "Configuring Application"
chmod +x /opt/fleet/fleet
JWT_KEY=$(openssl rand -base64 32)
cat <<EOF >/opt/fleet/.env
FLEET_MYSQL_ADDRESS=127.0.0.1:3306
FLEET_MYSQL_DATABASE=fleet
FLEET_MYSQL_USERNAME=fleet
FLEET_MYSQL_PASSWORD=${FLEET_DB_PASS}
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
After=network.target mysql.service
Requires=mysql.service

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
