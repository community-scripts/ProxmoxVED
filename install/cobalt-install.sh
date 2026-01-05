#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck / Community
# Author: Community Contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/imputnet/cobalt

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setup Cobalt"
$STD apt install -y git
NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs

$STD git clone https://github.com/imputnet/cobalt.git /opt/cobalt
cd /opt/cobalt
$STD pnpm install --frozen-lockfile
$STD pnpm --filter=@imput/cobalt-api build
$STD pnpm --filter=@imput/cobalt-web build

cat <<EOF >/etc/systemd/system/cobalt.service
[Unit]
Description=Cobalt API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cobalt/api
Environment="NODE_ENV=production"
Environment="API_URL=http://0.0.0.0:9000"
ExecStart=/usr/bin/node src/cobalt
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable --now cobalt

$STD apt install -y nginx
cat <<EOF >/etc/nginx/sites-available/cobalt
server {
    listen 8000;
    server_name _;
    
    root /opt/cobalt/web/build;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api {
        proxy_pass http://localhost:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/cobalt /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
msg_ok "Setup Cobalt"

motd_ssh
customize

cleanup_lxc
