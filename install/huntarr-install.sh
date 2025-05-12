#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: BiluliB
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/plexguide/Huntarr.io

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APPLICATION="huntarr"
REPO_NAME="Huntarr.io"

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  tar \
  unzip \
  jq \
  python3 \
  python3-pip \
  python3-venv
msg_ok "Installed System Dependencies"

msg_info "Setup ${APPLICATION}"
RELEASE=$(curl -fsSL https://api.github.com/repos/plexguide/Huntarr.io/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL -o "${RELEASE}.zip" "https://github.com/plexguide/Huntarr.io/archive/refs/tags/${RELEASE}.zip"
unzip -q "${RELEASE}.zip"
mv "${REPO_NAME}-${RELEASE}/" "/opt/${APPLICATION}"

echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

msg_info "Setting up Python Environment"
$STD python3 -m venv /opt/${APPLICATION}/venv
msg_ok "Created Python Virtual Environment"

msg_info "Installing Python Dependencies"
$STD /opt/${APPLICATION}/venv/bin/pip install --upgrade pip
$STD /opt/${APPLICATION}/venv/bin/pip install -r /opt/${APPLICATION}/requirements.txt
msg_ok "Installed Python Dependencies"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=Huntarr Service
After=network.target
[Service]
WorkingDirectory=/opt/${APPLICATION}
ExecStart=/opt/${APPLICATION}/venv/bin/python /opt/${APPLICATION}/main.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APPLICATION}
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f "${RELEASE}.zip"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
