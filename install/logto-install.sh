#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/logto-io/logto

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="logto" PG_DB_USER="logto" setup_postgresql_db
# db seed creates Logto's own tenant roles
$STD sudo -u postgres psql -c "ALTER ROLE logto CREATEROLE;"

fetch_and_deploy_gh_release "logto" "logto-io/logto" "prebuild" "latest" "/opt/logto" "logto.tar.gz"

msg_info "Configuring Logto"
# the Admin Console needs Web Crypto, which browsers only expose over HTTPS
create_self_signed_cert "logto"
mkdir -p /opt/logto_data
cat <<EOF >/opt/logto_data/.env
DB_URL=postgres://logto:${PG_DB_PASS}@localhost:5432/logto
ENDPOINT=https://${LOCAL_IP}:3001
ADMIN_ENDPOINT=https://${LOCAL_IP}:3002
HTTPS_CERT_PATH=/etc/ssl/logto/logto.crt
HTTPS_KEY_PATH=/etc/ssl/logto/logto.key
SECRET_VAULT_KEK=$(openssl rand -base64 32)
EOF
chmod 600 /opt/logto_data/.env
msg_ok "Configured Logto"

msg_info "Seeding Logto Database"
cd /opt/logto
$STD npm run cli db seed -- --swe --env /opt/logto_data/.env
msg_ok "Seeded Logto Database"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/logto.service
[Unit]
Description=Logto
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/logto/packages/core
EnvironmentFile=/opt/logto_data/.env
Environment=NODE_ENV=production
ExecStart=/usr/bin/node .
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now logto
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
