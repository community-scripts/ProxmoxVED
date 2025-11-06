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
$STD apt install -y \
    python3-opencv jq \
    libglib2.0-0 pciutils gcc musl-dev \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
    build-essential python3-dev python3-gi pkg-config libcairo2-dev gir1.2-glib-2.0 \
    cmake gfortran libopenblas-dev liblapack-dev libgirepository1.0-dev git libpq-dev
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PYTHON_VERSION="3.11" setup_uv

msg_info "Setting up PostgreSQL Database"
DB_NAME=viseron
DB_USER=viseron_usr
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
    echo "Viseron-Credentials"
    echo "Viseron Database User: $DB_USER"
    echo "Viseron Database Password: $DB_PASS"
    echo "Viseron Database Name: $DB_NAME"
} >>~/viseron.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Setting up Hardware Acceleration"
if [[ "$CTTYPE" == "0" ]]; then
   chgrp video /dev/dri
   chmod 755 /dev/dri
   chmod 660 /dev/dri/*
fi
msg_ok "Hardware Acceleration Configured"

fetch_and_deploy_gh_release "viseron" "roflcoopter/viseron"

msg_info "Setting up Python Environment"
uv venv --python "python3.11" /opt/viseron/.venv
uv pip install --python /opt/viseron/.venv/bin/python --upgrade pip setuptools wheel
msg_ok "Python Environment Setup"

msg_info "Setup Viseron (Patience)"
GPU_VENDOR=$(lspci | grep -E "VGA|3D" | grep -oE "NVIDIA|Intel|AMD" | head -n1)

case "$GPU_VENDOR" in
    NVIDIA)
        msg_info "NVIDIA GPU detected → Installing PyTorch with CUDA"
        UV_HTTP_TIMEOUT=1200 uv pip install --python /opt/viseron/.venv/bin/python \
            torch torchvision torchaudio
        msg_ok "Installed Torch with CUDA"
        ;;
    Intel)
        msg_info "Intel GPU detected → Installing PyTorch with Intel Extension (CPU wheels)"
        UV_HTTP_TIMEOUT=1200 uv pip install --python /opt/viseron/.venv/bin/python \
            torch torchvision torchaudio intel-extension-for-pytorch \
            --extra-index-url https://download.pytorch.org/whl/cpu
        msg_ok "Installed Torch with Intel Extension"
        ;;
    AMD)
        msg_info "AMD GPU detected → Installing PyTorch with ROCm"
        UV_HTTP_TIMEOUT=1200 uv pip install --python /opt/viseron/.venv/bin/python \
            torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/rocm6.0
        msg_ok "Installed Torch with ROCm"
        ;;
    CPU)
        msg_info "No GPU detected → Installing CPU-only PyTorch"
        UV_HTTP_TIMEOUT=1200 uv pip install --python /opt/viseron/.venv/bin/python \
            torch torchvision torchaudio \
            --extra-index-url https://download.pytorch.org/whl/cpu
        msg_ok "Installed Torch CPU-only"
        ;;
esac

UV_HTTP_TIMEOUT=600 uv pip install --python /opt/viseron/.venv/bin/python -e /opt/viseron/.
UV_HTTP_TIMEOUT=600 uv pip install --python /opt/viseron/.venv/bin/python -r /opt/viseron/requirements.txt

mkdir -p /config/{recordings,snapshots,segments,event_clips,thumbnails}
for d in recordings snapshots segments event_clips thumbnails; do
    ln -sfn "/config/$d" "/$d"
done
msg_ok "Setup Viseron"

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

storage:
  connection_string: postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME
  recordings: /recordings
  snapshots: /snapshots
  segments: /segments
  event_clips: /event_clips
  thumbnails: /thumbnails
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
ExecStart=/opt/viseron/.venv/bin/python -m viseron --config /config/viseron.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now viseron
msg_ok "Created Systemd Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned"
