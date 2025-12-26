#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: wendyliga
# License: MIT | https://github.com/wendyliga/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/DonutWare/Fladder

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  wget \
  unzip \
  nginx
msg_ok "Installed Dependencies"

msg_info "Installing ${APPLICATION}"
# Get latest version from GitHub
RELEASE=$(curl -fsSL https://api.github.com/repos/DonutWare/Fladder/releases/latest | \
    grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
cd /opt
$STD wget -q "https://github.com/DonutWare/Fladder/releases/download/${RELEASE}/Fladder-Web-${RELEASE#v}.zip"
$STD unzip -o "Fladder-Web-${RELEASE#v}.zip" -d fladder

rm -f "Fladder-Web-${RELEASE#v}.zip"
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed ${APPLICATION}"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/conf.d/fladder.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /opt/fladder;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
systemctl enable -q --now nginx
systemctl reload nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
