#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/emqx/MQTTX

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

fetch_and_deploy_gh_release "mqttx" "emqx/MQTTX" "tarball" "latest" "/opt/mqttx"

msg_info "Building MQTTX Web"
cd /opt/mqttx/web
$STD yarn install --frozen-lockfile
$STD yarn build
msg_ok "Built MQTTX Web"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/default
server {
    listen 80;

    root /opt/mqttx/web/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
systemctl restart nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
