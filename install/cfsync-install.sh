#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Yogev Bokobza
# License: MIT | https://github.com/YogevBokobza/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/koen01/CFSync

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  git \
  python3 \
  python3-venv \
  python3-pip \
  sshpass
msg_ok "Installed Dependencies"

if [[ -z "${var_printer_ip:-}" ]]; then
  read -r -p "${TAB3}Printer IP address [192.168.1.1]: " var_printer_ip
fi
PRINTER_IP="${var_printer_ip:-192.168.1.1}"

if [[ -z "${var_filament_diameter:-}" ]]; then
  read -r -p "${TAB3}Filament diameter in mm [1.75]: " var_filament_diameter
fi
FILAMENT_DIAMETER="${var_filament_diameter:-1.75}"

if [[ -z "${var_spoolman_url:-}" ]]; then
  read -r -p "${TAB3}Spoolman URL (leave blank to skip, e.g. http://192.168.1.x:7912): " var_spoolman_url
fi
SPOOLMAN_URL="${var_spoolman_url:-}"

SPOOLMAN_MODE="direct"
if [[ -n "${SPOOLMAN_URL}" ]]; then
  if [[ -z "${var_spoolman_mode:-}" ]]; then
    read -r -p "${TAB3}Spoolman mode — direct or moonraker [direct]: " var_spoolman_mode
  fi
  SPOOLMAN_MODE="${var_spoolman_mode:-direct}"
  if [[ "${SPOOLMAN_MODE}" != "direct" && "${SPOOLMAN_MODE}" != "moonraker" ]]; then
    SPOOLMAN_MODE="direct"
  fi
fi

msg_info "Installing CFSync"
git clone -q --depth 1 --branch spoolman https://github.com/koen01/CFSync.git /opt/cfsync
python3 -m venv /opt/cfsync/venv
/opt/cfsync/venv/bin/pip install -q --upgrade pip
/opt/cfsync/venv/bin/pip install -q -r /opt/cfsync/requirements.txt
mkdir -p /opt/cfsync/data
cat <<EOF >/opt/cfsync/data/config.json
{
  "printer_url": "${PRINTER_IP}",
  "filament_diameter_mm": ${FILAMENT_DIAMETER},
  "spoolman_url": "${SPOOLMAN_URL}",
  "spoolman_mode": "${SPOOLMAN_MODE}"
}
EOF
git -C /opt/cfsync rev-parse --short HEAD >/opt/CFSync_version.txt
msg_ok "Installed CFSync"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/cfsync.service
[Unit]
Description=CFSync Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cfsync
ExecStart=/opt/cfsync/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8005
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now cfsync
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned up"
