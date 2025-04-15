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
    cmake \
    git \
    libssl-dev \
    libjpeg-dev \
    zlib1g-dev \
    snapserver \
    pkg-config
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-venv
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
msg_ok "Setup Python3"

msg_info "Setup Music Assistant"
$STD fetch_and_deploy_gh_release music-assistant/server
cd /opt/musicassistant
$STD pip3 install uv
$STD pip install --upgrade pip uv
$STD python3 -m venv .venv
$STD source .venv/bin/activate
$STD uv pip install .
msg_ok "Setup Music Assistant"

msg_info "Adding AirPlay Support"
cd /usr/local/src
git clone https://github.com/music-assistant/libraop.git
cd libraop
git submodule update --init
./build.sh
msg_ok "Added AirPlay Support"

msg_info "Creating systemd service"
cat <<EOF >/etc/systemd/system/musicassistant.service
[Unit]
Description=Music Assistant
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/musicassistant
ExecStart=/opt/musicassistant/.venv/bin/mass
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
