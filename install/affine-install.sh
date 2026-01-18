#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/toeverything/AFFiNE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  pkg-config \
  openssl \
  libssl-dev \
  libjemalloc2 \
  redis-server \
  nginx
msg_ok "Installed Dependencies"

PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="affine" PG_DB_USER="affine" setup_postgresql_db
NODE_VERSION="22" setup_nodejs
setup_rust
import_local_ip

fetch_and_deploy_gh_release "affine_app" "toeverything/AFFiNE" "tarball" "latest" "/opt/affine"

msg_info "Setting up Directories"
rm -rf /root/.affine
mkdir -p /root/.affine/{storage,config}
msg_ok "Set up Directories"

msg_info "Configuring Environment"
SECRET_KEY=$(openssl rand -hex 32)
cat <<EOF >/opt/affine/.env
NODE_ENV=production
AFFINE_SERVER_PORT=3010
AFFINE_SERVER_HOST=${LOCAL_IP}
AFFINE_SERVER_EXTERNAL_URL=http://${LOCAL_IP}:3010
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
REDIS_SERVER_HOST=localhost
REDIS_SERVER_PORT=6379
AFFINE_INDEXER_ENABLED=false
NODE_OPTIONS=--max-old-space-size=4096
SECRET_KEY=${SECRET_KEY}
EOF
msg_ok "Configured Environment"

msg_info "Building AFFiNE (this will take 20-30 minutes)"
cd /opt/affine
source /root/.profile
export PATH="/root/.cargo/bin:$PATH"

set -a && source /opt/affine/.env && set +a

$STD corepack enable
$STD corepack prepare yarn@stable --activate
$STD yarn install
$STD yarn build
msg_ok "Built AFFiNE"

msg_info "Running Initial Migration"
cd /opt/affine/packages/backend/server
$STD node ./scripts/self-host-predeploy.js
msg_ok "Ran Initial Migration"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/affine-web.service
[Unit]
Description=AFFiNE Web Server
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/affine/packages/backend/server
EnvironmentFile=/opt/affine/.env
Environment=LD_PRELOAD=libjemalloc.so.2
ExecStart=/usr/bin/node ./dist/main.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/affine-worker.service
[Unit]
Description=AFFiNE Background Worker
After=network.target postgresql.service redis-server.service affine-web.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/affine/packages/backend/server
EnvironmentFile=/opt/affine/.env
Environment=LD_PRELOAD=libjemalloc.so.2
ExecStart=/usr/bin/node ./dist/main.js --worker
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now redis-server affine-web affine-worker
msg_ok "Created Services"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/affine.conf
upstream affine_backend {
    server 127.0.0.1:3010;
}

server {
    listen 80;
    server_name _;

    client_max_body_size 100M;

    location / {
        proxy_pass http://affine_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_redirect off;
        proxy_buffering off;
    }
}
EOF
ln -sf /etc/nginx/sites-available/affine.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl enable -q --now nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
