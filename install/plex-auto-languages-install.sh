#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Shaalan
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RemiRigal/Plex-Auto-Languages

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  curl \
  ca-certificates
msg_ok "Installed Dependencies"

msg_info "Setting up Python3"
$STD apt-get install -y \
  python3 \
  python3-pip \
  python3-venv
msg_ok "Set up Python3"

msg_info "Installing ${APP}"
cd /opt || exit
$STD git clone https://github.com/RemiRigal/Plex-Auto-Languages.git /opt/plex-auto-languages
$STD python3 -m venv /opt/plex-auto-languages/venv
$STD /opt/plex-auto-languages/venv/bin/pip install --upgrade pip
$STD /opt/plex-auto-languages/venv/bin/pip install -r /opt/plex-auto-languages/requirements.txt
msg_ok "Installed ${APP}"

msg_info "Creating Configuration"
mkdir -p /opt/plex-auto-languages/config
cat <<'EOF' >/opt/plex-auto-languages/config/config.yaml
plexautolanguages:
  update_level: "show"
  update_strategy: "all"
  trigger_on_play: true
  trigger_on_scan: true
  trigger_on_activity: false
  refresh_library_on_scan: true
  ignore_labels:
    - PAL_IGNORE

  plex:
    url: "http://PLEX_IP:32400"
    token: "CHANGE_ME"

  scheduler:
    enable: true
    schedule_time: "02:00"

  notifications:
    enable: false

  debug: false
EOF
msg_ok "Created Configuration"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/plex-auto-languages.service
[Unit]
Description=Plex Auto Languages
Documentation=https://github.com/RemiRigal/Plex-Auto-Languages
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/plex-auto-languages
ExecStart=/opt/plex-auto-languages/venv/bin/python3 main.py -c /opt/plex-auto-languages/config/config.yaml
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now plex-auto-languages
msg_ok "Created Service"

motd_ssh_info
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
