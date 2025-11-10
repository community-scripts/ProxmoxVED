#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: kairosys-dev
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://retype.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  nodejs \
  npm
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="node-gyp" setup_nodejs

msg_info "Setup ${APPLICATION}"
$STD npm install retypeapp --global
RELEASE=$(curl -fsSL https://api.github.com/repos/retypeapp/retype/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
echo "${RELEASE}" >/opt/"${APPLICATION}"_version.txt
msg_ok "Setup ${APPLICATION}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/"${APPLICATION}".service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
ExecStart=retype start --host 0.0.0.0
Restart=always
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now "${APPLICATION}"
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
