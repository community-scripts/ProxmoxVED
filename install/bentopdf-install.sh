#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/alam00000/bentopdf

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  nginx
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
fetch_and_deploy_gh_release "bentopdf" "alam00000/bentopdf" "tarball" "latest" "/opt/bentopdf"

msg_info "Setup BentoPDF"
cd /opt/bentopdf
$STD npm ci --no-audit --no-fund
$STD npm run build -- --mode production
cp -r /opt/bentopdf/dist/* /usr/share/nginx/html/
cp /opt/bentopdf/nginx.conf /etc/nginx/nginx.conf
mkdir -p /etc/nginx/tmp
useradd -M -s /usr/sbin/nologin -r -d /usr/share/nginx/html nginx
chown -R nginx:nginx {/usr/share/nginx/html,/etc/nginx/tmp,/etc/nginx/nginx.conf,/var/log/nginx}
msg_ok "Setup BentoPDF"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bentopdf.service
[Unit]
Description=BentoPDF Service
After=network.target

[Service]
Type=simple
User=nginx
Group=nginx
ExecStart=/sbin/nginx -g "daemon off;"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl -q enable --now bentopdf
msg_ok "Created & started service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned"
