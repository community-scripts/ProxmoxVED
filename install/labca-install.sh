#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/hakwerk/labca

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "labca-gui" "hakwerk/labca" "binary"

mkdir -p /etc/labca

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/labca.service
[Unit]
Description=LabCA GUI Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=30
StartLimitBurst=3

[Service]
Type=simple
WorkingDirectory=/etc/labca
ExecStart=/usr/bin/labca-gui -config /etc/labca/config.json -port 3000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now labca
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
