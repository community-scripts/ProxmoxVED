#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/clawdbot/clawdbot

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
  git \
  nginx
msg_ok "Installed Dependencies"

NODE_VERSION="24" NODE_MODULE="clawdbot@latest" setup_nodejs
import_local_ip


msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/clawdbot
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:18791;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/clawdbot /etc/nginx/sites-enabled/clawdbot
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
$STD systemctl enable -q --now nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc

