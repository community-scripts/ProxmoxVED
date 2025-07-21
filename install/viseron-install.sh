#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: jetonr
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/roflcoopter/viseron

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PYTHON_VERSION="3.12" setup_uv

msg_info "Installing Dependencies"
$STD apt-get install -y \
  python3 python3-pip python3-venv \
  python3-opencv \
  libgl1-mesa-glx libglib2.0-0 \
  libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav
msg_ok "Installed Dependencies"

msg_info "Setting up Python Environment with uv"
cd /opt
uv venv viseron
source viseron/bin/activate
uv pip install --upgrade pip setuptools wheel
msg_ok "Python Environment Setup (uv)"

msg_info "Installing Viseron"
RELEASE=$(curl -s https://api.github.com/repos/roflcoopter/viseron/releases/latest | jq -r '.tag_name')
uv pip install viseron==${RELEASE#v}
ln -s /opt/viseron/bin/viseron /usr/local/bin/viseron
msg_ok "Installed Viseron $RELEASE"

msg_info "Creating Configuration Directory"
mkdir -p /config
mkdir -p /config/recordings
mkdir -p /config/logs
msg_ok "Created Configuration Directory"

msg_info "Creating Default Configuration"
cat <<EOF >/config/viseron.yaml
# Viseron Configuration
# https://github.com/roflcoopter/viseron

# Logging
logging:
  level: INFO
  file: /config/logs/viseron.log

# Web Interface
web:
  host: 0.0.0.0
  port: 8888

# Cameras
cameras:
  # Example camera configuration
  # camera_name:
  #   host: 192.168.1.100
  #   port: 554
  #   username: admin
  #   password: password
  #   path: /stream
  #   fps: 5
  #   width: 1920
  #   height: 1080

# Object Detection
object_detection:
  type: opencv
  confidence: 0.5
  labels:
    - person
    - car
    - truck
    - bus
    - motorcycle
    - bicycle

# Recording
recording:
  enabled: true
  path: /config/recordings
  max_size: 10GB
  max_age: 7d

# Motion Detection
motion_detection:
  enabled: true
  threshold: 25
  sensitivity: 0.8
EOF
msg_ok "Created Default Configuration"

msg_info "Creating Systemd Service"
cat <<EOF >/etc/systemd/system/viseron.service
[Unit]
Description=Viseron NVR Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/viseron
Environment=PATH=/opt/viseron/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/viseron/bin/viseron --config /config/viseron.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now viseron
msg_ok "Created Systemd Service"

msg_info "Setting up Hardware Acceleration"
if [[ "$CTTYPE" == "0" ]]; then
    chgrp video /dev/dri
    chmod 755 /dev/dri
    chmod 660 /dev/dri/*
fi
msg_ok "Hardware Acceleration Configured"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
