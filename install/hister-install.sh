#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/asciimoo/hister

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ARCH=$(dpkg --print-architecture)
fetch_and_deploy_gh_release "hister" "asciimoo/hister" "singlefile" "latest" "/usr/local/bin" "hister_*_linux_${ARCH}"

msg_info "Configuring Hister"
mkdir -p /opt/hister/data /etc/hister
cat <<EOF >/etc/hister/hister.env
HISTER_DATA_DIR=/opt/hister/data
HISTER__SERVER__ADDRESS=0.0.0.0:4433
EOF
msg_ok "Configured Hister"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/hister.service
[Unit]
Description=Hister Search Engine
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/hister/hister.env
ExecStart=/usr/local/bin/hister listen
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hister
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
