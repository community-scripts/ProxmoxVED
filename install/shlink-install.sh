#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://shlink.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PHP_VERSION="8.5" setup_php
setup_mariadb
MARIADB_DB_NAME="shlink" MARIADB_DB_USER="shlink" setup_mariadb_db

fetch_and_deploy_gh_release "shlink" "shlinkio/shlink" "prebuild" "latest" "/opt/shlink" "shlink*_php8.5_dist.zip"

msg_info "Setting up Application"
cd /opt/shlink
$STD php ./vendor/bin/rr get --no-interaction --location bin/
chmod +x bin/rr
chmod -R 775 data
cat <<EOF >/opt/shlink/.env
DEFAULT_DOMAIN=${LOCAL_IP}:8080
IS_HTTPS_ENABLED=false
DB_DRIVER=maria
DB_NAME=${MARIADB_DB_NAME}
DB_USER=${MARIADB_DB_USER}
DB_PASSWORD=${MARIADB_DB_PASS}
DB_HOST=127.0.0.1
DB_PORT=3306
EOF
$STD php bin/cli db:create --no-interaction
$STD php bin/cli db:migrate --no-interaction
INITIAL_API_KEY=$($STD php bin/cli api-key:generate --name=default 2>&1 | grep -oP '[A-Za-z0-9_-]{20,}' | head -1)
if [[ -n "$INITIAL_API_KEY" ]]; then
  echo "INITIAL_API_KEY=${INITIAL_API_KEY}" >>/opt/shlink/.env
fi
msg_ok "Set up Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/shlink.service
[Unit]
Description=Shlink URL Shortener
After=network.target mariadb.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/shlink
EnvironmentFile=/opt/shlink/.env
ExecStart=/opt/shlink/bin/rr serve -c config/roadrunner/.rr.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now shlink
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
