#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: davalanche
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/mylar3/mylar3

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
echo "deb http://deb.debian.org/debian bookworm non-free non-free-firmware" >/etc/apt/sources.list.d/non-free.list
$STD apt-get update
$STD apt-get install -y unrar
rm /etc/apt/sources.list.d/non-free.list
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
fetch_and_deploy_gh_release "mylar3" "mylar3/mylar3"

msg_info "Setup Mylar3"
mkdir -p /opt/mylar3
mkdir -p /opt/mylar3-data
$STD uv pip install --no-cache-dir -r /opt/mylar3/requirements.txt --system
msg_ok "Setup Mylar3"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mylar3.service
[Unit]
Description=Mylar3 Service
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/mylar3/Mylar.py --daemon --nolaunch --datadir=/opt/mylar3-data
GuessMainPID=no
Type=forking
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mylar3
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
