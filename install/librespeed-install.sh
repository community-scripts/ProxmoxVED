#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: elvito
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/librespeed/speedtest

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y \
  caddy \
  php-fpm
msg_ok "Installed Dependencies"

msg_info "Installing librespeed"
temp_file=$(mktemp)
RELEASE=$(curl -fsSL https://api.github.com/repos/librespeed/speedtest/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
curl -fsSL "https://github.com/librespeed/speedtest/archive/refs/tags/${RELEASE}.zip" -o "$temp_file"
mkdir -p /opt/librespeed
mkdir -p /temp
unzip -q "$temp_file" -d /temp
cd /temp/speedtest-"${RELEASE}"
cp -u favicon.ico index.html speedtest.js speedtest_worker.js /opt/librespeed/
cp -ru backend results /opt/librespeed/

cat <<EOF >/etc/caddy/Caddyfile
:80 {
        root * /opt/librespeed
        file_server
        php_fastcgi unix//run/php/php-fpm.sock
}
EOF

systemctl restart caddy
echo "${RELEASE}" >/opt/"${APP}_version.txt"
msg_ok "Installation completed"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /temp
rm -f "$temp_file"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
