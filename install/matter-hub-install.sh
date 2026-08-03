#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RiDDiX/home-assistant-matter-hub

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="24" NODE_MODULE="pnpm@^10" setup_nodejs

fetch_and_deploy_gh_release "matter-hub" "RiDDiX/home-assistant-matter-hub" "tarball"

msg_info "Building Matter Hub"
cd /opt/matter-hub
$STD pnpm install --frozen-lockfile
$STD pnpm build
msg_ok "Built Matter Hub"

msg_info "Configuring Matter Hub"
mkdir -p /opt/matter-hub_data
cat <<EOF >/opt/matter-hub.env
HAMH_HOME_ASSISTANT_URL=http://CHANGE_ME:8123/
HAMH_HOME_ASSISTANT_ACCESS_TOKEN=CHANGE_ME
HAMH_HTTP_PORT=8482
HAMH_LOG_LEVEL=info
EOF
chmod 600 /opt/matter-hub.env
msg_ok "Configured Matter Hub"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/matter-hub.service
[Unit]
Description=Home Assistant Matter Hub
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/matter-hub
EnvironmentFile=/opt/matter-hub.env
ExecStart=/usr/bin/node /opt/matter-hub/apps/home-assistant-matter-hub/dist/backend/cli.js start --storage-location=/opt/matter-hub_data
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now matter-hub
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
