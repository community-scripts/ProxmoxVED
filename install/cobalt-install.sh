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

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  git \
  ca-certificates \
  gnupg \
  python3 \
  build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

msg_info "Installing pnpm"
$STD npm install -g pnpm
msg_ok "Installed pnpm"

msg_info "Cloning Cobalt Repository"
$STD git clone https://github.com/imputnet/cobalt.git /opt/cobalt
cd /opt/cobalt
msg_ok "Cloned Cobalt Repository"

msg_info "Installing Cobalt Dependencies"
$STD pnpm install --frozen-lockfile
msg_ok "Installed Cobalt Dependencies"

msg_info "Building Cobalt API"
$STD pnpm --filter=@imput/cobalt-api build
msg_ok "Built Cobalt API"

msg_info "Building Cobalt Web"
$STD pnpm --filter=@imput/cobalt-web build
msg_ok "Built Cobalt Web"

msg_info "Creating Cobalt API Service"
cat <<EOF >/etc/systemd/system/cobalt-api.service
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
$STD systemctl enable --now cobalt-api.service
msg_ok "Created Cobalt API Service"

msg_info "Installing and Configuring Nginx"
$STD apt-get install -y nginx
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
msg_ok "Installed and Configured Nginx"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
