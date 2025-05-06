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

NODE_VERSION="22" install_node_and_modules

msg_info "Installing Fumadocs"
fetch_and_deploy_gh_release fuma-nama/fumadocs
# temp_file=$(mktemp)
# RELEASE=$(curl -fsSL https://api.github.com/repos/fuma-nama/fumadocs/releases/latest | grep '"tag_name"' | awk -F '"' '{print $4}')
export NODE_OPTIONS="--max-old-space-size=4096"
# curl -fsSL "https://github.com/fuma-nama/fumadocs/archive/refs/tags/${RELEASE}.tar.gz" -o "$temp_file"
# tar -xzf $temp_file
# mv fumadocs-* "/opt/fumadocs"
cd /opt/fumadocs
$STD pnpm install
pnpm create fumadocs-app
# expect "Project name"
# send "my-app\r"
# expect "Choose a template"
# send "Next.js: Fumadocs MDX\r"
# expect "Use \`/src\` directory?"
# send "No\r"
# expect "Add default ESLint configuration?"
# send "No\r"
# expect "Do you want to install packages automatically?*"
# send "Yes\r"
# expect eof
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
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
msg_ok "Created Service"
EOF

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
