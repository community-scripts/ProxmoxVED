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

msg_info "Installing Dependencies"
$STD apt-get install -y \
    python3 python3-pip python3-venv \
    git curl wget \
    libgl1-mesa-glx libglib2.0-0 \
    libsm6 libxext6 libxrender-dev \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
    libgstreamer-plugins-bad1.0-0 gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav \
    gstreamer1.0-tools gstreamer1.0-x gstreamer1.0-alsa \
    gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 \
    gstreamer1.0-pulseaudio \
    libavcodec-dev libavformat-dev libswscale-dev \
    libv4l-dev libxvidcore-dev libx264-dev \
    libjpeg-dev libpng-dev libtiff-dev \
    libatlas-base-dev gfortran \
    libhdf5-dev libhdf5-serial-dev \
    libhdf5-103 libqtgui4 libqtwebkit4 libqt4-test python3-pyqt5 \
    libgtk-3-dev libcanberra-gtk3-module \
    libgirepository1.0-dev libcairo2-dev pkg-config \
    libcblas-dev libopenblas-dev liblapack-dev \
    libsm6 libxext6 libxrender-dev libxss1 \
    libgconf-2-4 libasound2
msg_ok "Installed Dependencies"

msg_info "Setting up Python Environment"
cd /opt
python3 -m venv viseron
source viseron/bin/activate
pip install --upgrade pip setuptools wheel
msg_ok "Python Environment Setup"

msg_info "Installing Viseron"
RELEASE=$(curl -s https://api.github.com/repos/roflcoopter/viseron/releases/latest | jq -r '.tag_name')
pip install viseron==${RELEASE#v}
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
systemctl enable viseron
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

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}Viseron setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8888${CL}"
echo -e "${INFO}${YW} Configuration file: /config/viseron.yaml${CL}"
echo -e "${INFO}${YW} Logs: /config/logs/viseron.log${CL}"
echo -e "${INFO}${YW} Recordings: /config/recordings${CL}"
echo -e "${INFO}${YW} Contributor: jetonr${CL}"
