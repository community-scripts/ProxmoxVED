#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://docs.seerr.dev/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y build-essential
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "seer" "seerr-team/seerr" "tarball" "latest"

pnpm_desired=$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/seer/package.json)
NODE_VERSION="22" NODE_MODULE="pnpm@$pnpm_desired" setup_nodejs

msg_info "Installing Seer (Patience)"
export CYPRESS_INSTALL_BINARY=0
cd /opt/seer
$STD pnpm install --frozen-lockfile
export NODE_OPTIONS="--max-old-space-size=3072"
$STD pnpm build
mkdir -p /etc/seer/
cat <<EOF >/etc/seer/seer.conf
## Seer's default port is 5055, if you want to use both, change this.
## specify on which port to listen
PORT=5055

## specify on which interface to listen, by default seer listens on all interfaces
HOST=0.0.0.0

## Uncomment if you want to force Node.js to resolve IPv4 before IPv6 (advanced users only)
# FORCE_IPV4_FIRST=true
EOF
msg_ok "Installed Seer"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/seer.service
[Unit]
Description=Seer Service
After=network.target

[Service]
EnvironmentFile=/etc/seer/seer.conf
Environment=NODE_ENV=production
Type=exec
WorkingDirectory=/opt/seer
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now seer
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
