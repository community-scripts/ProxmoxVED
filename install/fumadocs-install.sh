#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  ca-certificates \
  expect
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="pnpm@latest" install_node_and_modules

msg_info "Installing Fumadocs"
fetch_and_deploy_gh_release fuma-nama/fumadocs
export NODE_OPTIONS="--max-old-space-size=4096"
cd /opt/fumadocs
$STD pnpm install
pnpm create fumadocs-app
msg_ok "Installed Fumadocs"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/fumadocs.service
[Unit]
Description=Fumadocs Documentation Server
After=network.target

[Service]
WorkingDirectory=/opt/fumadocs
ExecStart=/usr/bin/pnpm run dev
Restart=always

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
