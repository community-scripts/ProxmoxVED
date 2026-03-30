#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/drawdb-io/drawdb

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y caddy
msg_ok "Installed Dependencies"

NODE_VERSION="20" setup_nodejs
fetch_and_deploy_gh_tag "drawdb" "drawdb-io/drawdb" "latest" "/opt/drawdb"

msg_info "Building Frontend"
cd /opt/drawdb
$STD npm ci
NODE_OPTIONS="--max-old-space-size=4096" $STD npm run build
msg_ok "Built Frontend"

msg_info "Configuring Caddy"
cat <<EOF >/etc/caddy/Caddyfile
:3000 {
    root * /opt/drawdb/dist
    file_server
    try_files {path} /index.html
}
EOF
systemctl reload caddy
msg_ok "Configured Caddy"

motd_ssh
customize
cleanup_lxc
