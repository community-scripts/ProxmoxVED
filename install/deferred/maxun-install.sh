#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  redis-server \
  nginx \
  libgbm1 \
  libnss3 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libdrm2 \
  libxkbcommon0 \
  libglib2.0-0 \
  libdbus-1-3 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxi6 \
  libxtst6 \
  libxrandr2 \
  libasound2 \
  libxss1 \
  libxinerama1
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
NODE_VERSION="20" setup_nodejs
PG_DB_NAME="maxun_db" PG_DB_USER="maxun" setup_postgresql_db
fetch_and_deploy_gh_release "maxun" "getmaxun/maxun" "tarball" "latest" "/opt/maxun"

msg_info "Setting up Variables"
MINIO_USER="minio_admin"
MINIO_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c48)
ENCRYPTION_KEY=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c32)
LOCAL_IP=$(hostname -I | awk '{print $1}')
msg_ok "Variables configured"

msg_info "Setting up MinIO"
mkdir -p /opt/minio_data
cd /tmp
curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio.deb -o minio.deb
$STD dpkg -i minio.deb
rm -f /tmp/minio.deb

cat <<EOF >/etc/default/minio
MINIO_ROOT_USER=${MINIO_USER}
MINIO_ROOT_PASSWORD=${MINIO_PASS}
MINIO_VOLUMES="/opt/minio_data"
MINIO_OPTS="--console-address :9001"
EOF

cat <<EOF >/etc/systemd/system/minio.service
[Unit]
Description=MinIO Object Storage
Documentation=https://docs.min.io
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/default/minio
ExecStart=/usr/bin/minio server \$MINIO_VOLUMES \$MINIO_OPTS
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now minio
msg_ok "MinIO configured"

msg_info "Setting up Redis"
systemctl enable -q --now redis-server
msg_ok "Redis configured"

msg_info "Installing Maxun (Patience)"
cd /opt/maxun
cat <<EOF >/opt/maxun/.env
NODE_ENV=production
JWT_SECRET=${JWT_SECRET}
DB_NAME=${PG_DB_NAME}
DB_USER=${PG_DB_USER}
DB_PASSWORD=${PG_DB_PASS}
DB_HOST=localhost
DB_PORT=5432
ENCRYPTION_KEY=${ENCRYPTION_KEY}
SESSION_SECRET=${SESSION_SECRET}

MINIO_ENDPOINT=localhost
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ACCESS_KEY=${MINIO_USER}
MINIO_SECRET_KEY=${MINIO_PASS}

REDIS_HOST=127.0.0.1
REDIS_PORT=6379

BACKEND_PORT=8080
FRONTEND_PORT=5173
BACKEND_URL=http://${LOCAL_IP}:8080
PUBLIC_URL=http://${LOCAL_IP}
VITE_BACKEND_URL=http://${LOCAL_IP}:8080
VITE_PUBLIC_URL=http://${LOCAL_IP}

MAXUN_TELEMETRY=false
EOF
$STD npm install --legacy-peer-deps
cd /opt/maxun/maxun-core
$STD npm install --legacy-peer-deps
cd /opt/maxun
msg_ok "Maxun dependencies installed"

msg_info "Installing Playwright/Chromium"
$STD npm install playwright
$STD npx playwright install --with-deps chromium
msg_ok "Playwright/Chromium installed"

msg_info "Building Maxun"
$STD npm run build:server
$STD npm run build
msg_ok "Maxun built"

msg_info "Setting up nginx"
mkdir -p /var/www/maxun
cp -r /opt/maxun/dist/* /var/www/maxun/

cat <<'EOF' >/etc/nginx/sites-available/maxun
server {
    listen 80;
    server_name _;

    root /var/www/maxun;
    index index.html;

    # Frontend
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Backend API Proxy
    location ~ ^/(auth|storage|record|workflow|robot|proxy|api-docs|api|webhook)(/|$) {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 120s;
        proxy_send_timeout 60s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/maxun /etc/nginx/sites-enabled/maxun
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
systemctl enable -q --now nginx
msg_ok "nginx configured"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/maxun.service
[Unit]
Description=Maxun Web Scraping Service
After=network.target postgresql.service redis-server.service minio.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/maxun
EnvironmentFile=/opt/maxun/.env
ExecStart=/usr/bin/node server/dist/server/src/server.js
Restart=always
RestartSec=5
Environment=NODE_OPTIONS=--max-old-space-size=512

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now maxun
msg_ok "Service created"

motd_ssh
customize
cleanup_lxc
