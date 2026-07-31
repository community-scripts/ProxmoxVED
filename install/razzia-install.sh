#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Owen Voke (owenvoke)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Ralex91/Razzia

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

NODE_VERSION="24" NODE_MODULE="pnpm@11" setup_nodejs
fetch_and_deploy_gh_release "razzia" "Ralex91/Razzia" "tarball"

msg_info "Building Razzia"
cd /opt/razzia
$STD pnpm install --frozen-lockfile
$STD pnpm build
msg_ok "Built Razzia"

msg_info "Configuring Razzia"
mkdir -p /opt/razzia-config
cat <<EOF >/opt/razzia-config/game.json
{
  "managerPassword": "$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
}
EOF
msg_ok "Configured Razzia"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/razzia.service
[Unit]
Description=Razzia Socket Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/razzia/packages/socket
Environment=NODE_ENV=production
Environment=CONFIG_PATH=/opt/razzia-config
ExecStart=/usr/bin/node /opt/razzia/packages/socket/dist/index.cjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now razzia
msg_ok "Created Service"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/razzia
server {
  listen 3000;
  server_name _;

  root /opt/razzia/packages/web/dist;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  location /branding/ {
    alias /opt/razzia-config/branding/;
  }

  location /ws {
    proxy_pass http://127.0.0.1:3001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
}
EOF
ln -sf /etc/nginx/sites-available/razzia /etc/nginx/sites-enabled/razzia
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
systemctl reload nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
