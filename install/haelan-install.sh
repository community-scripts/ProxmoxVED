#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Bardesss
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bardesss/haelan

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "haelan" "bardesss/haelan" "tarball"

# Read out of the deployed tree rather than pinned here, so the two cannot drift.
PNPM_VERSION=$(sed -n 's/.*"packageManager": "pnpm@\([^"+]*\).*/\1/p' /opt/haelan/package.json)
NODE_VERSION="24" NODE_MODULE="pnpm@${PNPM_VERSION:-11.22.0}" setup_nodejs

msg_info "Building Haelan"
cd /opt/haelan
$STD pnpm install --frozen-lockfile
# Builds apps/web/dist and nothing else. The server is TypeScript that Node runs directly through
# type stripping, which is also why NODE_VERSION is 24 rather than the 22.13 floor in engines.
$STD pnpm build
msg_ok "Built Haelan"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/haelan.service
[Unit]
Description=Haelan
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/haelan
Environment=NODE_ENV=production
# Outside /opt/haelan deliberately: an update is a clean re-deploy of that directory, so the
# database, the encryption key and the backups have to live somewhere it cannot reach.
Environment=HAELAN_DATA_DIR=/opt/haelan_data
ExecStart=/usr/bin/node /opt/haelan/apps/server/src/index.ts
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now haelan
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
