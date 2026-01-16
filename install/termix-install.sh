#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Termix-SSH/Termix

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  python3 \
  make \
  g++ \
  nginx \
  openssl \
  gettext-base
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
fetch_and_deploy_gh_release "termix" "Termix-SSH/Termix"

msg_info "Building ${APPLICATION} (Patience)"
cd /opt/termix
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD npm install --ignore-scripts --force
$STD npm rebuild better-sqlite3 --force
$STD npm run build
$STD npm run build:backend
mkdir -p /opt/termix/data /opt/termix/uploads
msg_ok "Built ${APPLICATION}"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/termix.conf
server {
    listen 8080;
    server_name _;

    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        root /opt/termix/dist;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    location / {
        root /opt/termix/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location ~ ^/(users|version|releases|alerts|rbac|credentials|snippets|terminal|database|db|encryption|ssh|health)(/.*)?$ {
        proxy_pass http://127.0.0.1:30001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    location /ssh/websocket/ {
        proxy_pass http://127.0.0.1:30002/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    location ~ ^/status(/.*)?$ {
        proxy_pass http://127.0.0.1:30005;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location ~ ^/docker(/.*)?$ {
        proxy_pass http://127.0.0.1:30007;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/termix.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
msg_ok "Configured Nginx"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/termix.service
[Unit]
Description=Termix Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/termix
Environment=NODE_ENV=production
Environment=DATA_DIR=/opt/termix/data
Environment=PORT=30001
ExecStart=/usr/bin/node /opt/termix/dist/backend/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now termix
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
