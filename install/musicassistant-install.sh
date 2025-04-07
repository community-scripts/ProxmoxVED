#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT
# Source: https://github.com/music-assistant/server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  ffmpeg \
  build-essential \
  libffi-dev \
  libssl-dev \
  libjpeg-dev \
  zlib1g-dev \
  pkg-config
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
msg_ok "Setup Python3"

msg_info "Setup Music Assistant"
fetch_and_deploy_gh_release music-assistant/server
cd /opt/musicassistant
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip uv
uv pip install .
msg_ok "Setup Music Assistant"

msg_info "Creating systemd service"
cat <<EOF >/etc/systemd/system/musicassistant.service
[Unit]
Description=Music Assistant
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/musicassistant
Environment="PATH=/opt/musicassistant/venv/bin"
ExecStart=/opt/musicassistant/venv/bin/mass
Restart=always
RestartForceExitStatus=100

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now musicassistant
msg_ok "Started Music Assistant"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
