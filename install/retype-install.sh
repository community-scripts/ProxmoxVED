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

NODE_VERSION="22" NODE_MODULE="node-gyp" setup_nodejs

msg_info "Setup Retype"
$STD npm install retypeapp --global
RELEASE=$(curl -s https://registry.npmjs.org/retype | grep -Po '"latest":"\K[^"]+')
echo "${RELEASE}" >/opt/"${APPLICATION}"_version.txt
msg_ok "Setup Retype"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/Retype.service
[Unit]
Description=Retype Service
After=network.target

[Service]
ExecStart=retype start --host 0.0.0.0
Restart=always
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now Retype.service
msg_ok "Created Service"

motd_ssh
customize

cleanup_lxc
