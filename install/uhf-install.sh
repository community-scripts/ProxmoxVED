#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: zackwithak13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.uhfapp.com/server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setting Up Hardware Acceleration"
$STD apt-get -y install {va-driver-all,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools}
if [[ "$CTTYPE" == "0" ]]; then
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
  $STD adduser $(id -u -n) video
  $STD adduser $(id -u -n) render
fi
msg_ok "Set Up Hardware Acceleration"

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get -y install ffmpeg
msg_ok "Installed Dependencies"

msg_info "Installing UHF Server"
mkdir -p /etc/uhf-server
mkdir -p /var/lib/uhf-server/data
mkdir -p /var/lib/uhf-server/recordings
env_path="/etc/uhf-server/.env"
echo "API_HOST=0.0.0.0
API_PORT=7568
RECORDINGS_DIR=/var/lib/uhf-server/recordings
DB_PATH=/var/lib/uhf-server/data/db.json
LOG_LEVEL=INFO" >"${env_path}"
fetch_and_deploy_gh_release "comskip" "swapplications/comskip" "prebuild" "latest" "/opt/comskip" "comskip-x64-*.zip"
fetch_and_deploy_gh_release "uhf-server" "swapplications/uhf-server-dist" "prebuild" "latest" "/opt/uhf-server" "UHF.Server-linux-x64-*.zip"
msg_ok "Installed UHF Server"

msg_info "Creating Service"
service_path="/etc/systemd/system/uhf-server.service"
echo "[Unit]
Description=UHF Server service
After=syslog.target network-online.target
[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/uhf-server
EnvironmentFile=/etc/uhf-server/.env
ExecStart=/opt/uhf-server/uhf-server
[Install]
WantedBy=multi-user.target" >"${service_path}"
systemctl enable --now -q uhf-server.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
