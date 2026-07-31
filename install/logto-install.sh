#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://logto.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="logto" PG_DB_USER="logto" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

fetch_and_deploy_gh_release "logto" "logto-io/logto" "prebuild" "latest" "/opt/logto" "logto.tar.gz"

msg_info "Generating Self-Signed Certificate"
create_self_signed_cert "logto" "DNS:logto.${LOCAL_IP}.nip.io"
msg_ok "Generated Self-Signed Certificate"

msg_info "Configuring Logto"
DB_URL="postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}"
cat <<EOF >/opt/logto/.env
DB_URL=${DB_URL}
ENDPOINT=https://logto.${LOCAL_IP}.nip.io:3001
ADMIN_ENDPOINT=https://${LOCAL_IP}:3002
PORT=13001
ADMIN_PORT=13002
TRUST_PROXY_HEADER=1
EOF
msg_ok "Configured Logto"

msg_info "Seeding Database"
cd /opt/logto
DB_URL="${DB_URL}" $STD npm run cli db seed -- --swe
msg_ok "Seeded Database"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/logto.service
[Unit]
Description=Logto Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/logto/packages/core
EnvironmentFile=/opt/logto/.env
Environment=NODE_ENV=production
ExecStart=/usr/bin/node .
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now logto
msg_ok "Created Service"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/conf.d/logto.conf
server {
    listen 3001 ssl;
    http2 on;
    server_name _;
    ssl_certificate /etc/ssl/logto/logto.crt;
    ssl_certificate_key /etc/ssl/logto/logto.key;
    client_max_body_size 20M;

    location / {
        proxy_pass http://127.0.0.1:13001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 3002 ssl;
    http2 on;
    server_name _;
    ssl_certificate /etc/ssl/logto/logto.crt;
    ssl_certificate_key /etc/ssl/logto/logto.key;
    client_max_body_size 20M;

    location / {
        proxy_pass http://127.0.0.1:13002;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
