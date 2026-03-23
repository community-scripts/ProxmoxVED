#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: SystemIdleProcess
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Kometa-Team/Quickstart

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y python3-pip
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.13" setup_uv
fetch_and_deploy_gh_release "quickstart" "Kometa-Team/Quickstart" "tarball"

msg_info "Setup Quickstart"
cd /opt/quickstart || exit
$STD uv venv /opt/quickstart/config/.venv
source /opt/quickstart/config/.venv/bin/activate
$STD uv pip install --upgrade pip
$STD uv pip install -r requirements.txt
msg_ok "Setup Quickstart"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/quickstart.service
[Unit]
Description=Quickstart Service
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/quickstart
ExecStart=/opt/quickstart/config/.venv/bin/python3 quickstart.py
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now quickstart
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
