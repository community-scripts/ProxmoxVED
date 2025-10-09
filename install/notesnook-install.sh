#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/streetwriters/notesnook

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    make \
    git \
    caddy
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
fetch_and_deploy_gh_release "notesnook" "streetwriters/notesnook" "tarball"

msg_info "Configuring Notesnook (Patience)"
cd /opt/notesnook
export NODE_OPTIONS="--max-old-space-size=2560"
$STD npm install
$STD npm run build:web
msg_ok "Configured Notesnook"

msg_info "Configuring Caddy"
LOCAL_IP=$(hostname -I | awk '{print $1}')
cat <<EOF >/etc/caddy/Caddyfile
{
    email admin@example.com
}

${LOCAL_IP} {
    reverse_proxy 127.0.0.1:3000
}
EOF
msg_ok "Configured Caddy"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/notesnook.service
[Unit]
Description=Notesnook Service
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/notesnook
ExecStart=/usr/bin/npx serve apps/web/build
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl reload caddy
systemctl enable -q --now notesnook
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
