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
$STD apt-get install -y make git
msg_ok "Installed Dependencies"

NODE_MODULE="yarn" setup_nodejs

msg_info "Installing Notesnook (Patience)"
fetch_and_deploy_gh_release "notesnook" "streetwriters/notesnook" "tarball"
cd /opt/notesnook
export NODE_OPTIONS="--max-old-space-size=2560"
mkdir -p certs
$STD openssl req -x509 -newkey rsa:4096 -keyout certs/key.pem -out certs/cert.pem -days 365 -nodes -subj "/CN=localhost"
$STD npm install
$STD npm run build:web
msg_ok "Installed Notesnook"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/notesnook.service
[Unit]
Description=Notesnook Service
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/notesnook
ExecStart=/usr/bin/npx serve -l tcp://0.0.0.0:3000 apps/web/build --ssl-cert certs/cert.pem --ssl-key certs/key.pem
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now notesnook
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
