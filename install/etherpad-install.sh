#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: John McLear (JohnMcLear)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://etherpad.org

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  pkg-config \
  libsqlite3-dev
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Enabling pnpm via corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack enable
msg_ok "Enabled pnpm"

msg_info "Creating etherpad User"
useradd --system --create-home --home-dir /var/lib/etherpad --shell /usr/sbin/nologin etherpad
msg_ok "Created etherpad User"

fetch_and_deploy_gh_release "etherpad-lite" "ether/etherpad-lite" "tarball" "latest" "/opt/etherpad-lite"

msg_info "Building Etherpad"
cd /opt/etherpad-lite
$STD pnpm install --frozen-lockfile
$STD pnpm run build:etherpad
msg_ok "Built Etherpad"

msg_info "Configuring Etherpad"
cp /opt/etherpad-lite/settings.json.template /opt/etherpad-lite/settings.json
sed -i 's#"ip": *"127.0.0.1"#"ip": "0.0.0.0"#' /opt/etherpad-lite/settings.json
chown -R etherpad:etherpad /opt/etherpad-lite
msg_ok "Configured Etherpad"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/etherpad.service
[Unit]
Description=Etherpad Collaborative Editor
Documentation=https://etherpad.org/doc
After=network.target

[Service]
Type=simple
User=etherpad
Group=etherpad
WorkingDirectory=/opt/etherpad-lite
Environment=NODE_ENV=production
ExecStart=/usr/bin/env pnpm run prod
Restart=always
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now etherpad
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
