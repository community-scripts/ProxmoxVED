#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: pjona
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/tombii/better-ccflare

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "better-ccflare" "tombii/better-ccflare" "singlefile" "latest" "/opt/better-ccflare" "better-ccflare-linux-amd64"

msg_info "Creating Service"
mkdir -p /opt/better-ccflare/data
cat <<EOF >/etc/systemd/system/better-ccflare.service
[Unit]
Description=better-ccflare Claude API Load Balancer
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/better-ccflare
ExecStart=/opt/better-ccflare/better-ccflare
Restart=on-failure
RestartSec=5
Environment="PORT=8080"
Environment="BETTER_CCFLARE_HOST=0.0.0.0"
Environment="BETTER_CCFLARE_DB_PATH=/opt/better-ccflare/data/better-ccflare.db"

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now better-ccflare
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
