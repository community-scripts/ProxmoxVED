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
$STD apt-get install -y make
msg_ok "Installed Dependencies"

NODE_MODULE="yarn" install_node_and_modules

msg_info "Installing Notesnook"
fetch_and_deploy_gh_release "streetwriters/notesnook"
cd /opt/notesnook
#export NODE_OPTIONS="--max-old-space-size=2048"
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
ExecStart=/usr/bin/npx serve apps/web/build
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now notesnook
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f "$temp_file"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
