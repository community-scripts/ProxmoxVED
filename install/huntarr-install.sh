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
$STD apt-get install -y jq
msg_ok "Installed Dependencies"

msg_info "Installing Python"
$STD apt-get install -y \
  python3 \
  python3-venv
msg_ok "Installed Python"

msg_info "Setup uv"
setup_uv
msg_ok "Setup uv"

msg_info "Setting Up Huntarr"
RELEASE=$(curl -fsSL https://api.github.com/repos/plexguide/Huntarr.io/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
temp_file=$(mktemp)
$STD curl -fsSL -o "$temp_file" "https://github.com/plexguide/Huntarr.io/archive/refs/tags/${RELEASE}.zip"
$STD unzip -q "$temp_file"
$STD mv "${REPO_NAME}-${RELEASE}/" "/opt/${APPLICATION}"
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
$STD uv venv /opt/${APPLICATION}/venv
$STD uv pip install --python /opt/${APPLICATION}/venv/bin/python -r /opt/${APPLICATION}/requirements.txt
msg_ok "Setup Huntrarr Complete"

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
rm -f "$temp_file"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
