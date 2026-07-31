#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Darkrock-Studios/hammer-editor

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  unzip \
  fontconfig \
  libfreetype6
msg_ok "Installed Dependencies"

JAVA_VERSION="21" setup_java

fetch_and_deploy_gh_release "hammer" "Darkrock-Studios/hammer-editor" "prebuild" "latest" "/opt/hammer" "server.zip"

msg_info "Configuring Hammer Sync Server"
chmod +x /opt/hammer/bin/server
mkdir -p /opt/hammer_data
cat <<EOF >/etc/systemd/system/hammer.service
[Unit]
Description=Hammer Sync Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/hammer
Environment=SERVER_OPTS=-Duser.home=/opt/hammer_data
ExecStart=/opt/hammer/bin/server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hammer
msg_ok "Configured Hammer Sync Server"

motd_ssh
customize
cleanup_lxc
