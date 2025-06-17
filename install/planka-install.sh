#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/plankanban/planka

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
  unzip \
  build-essential
msg_ok "Installed dependencies"

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
fetch_and_deploy_gh_release "planka" "plankanban/planka" "prebuild" "latest" "/opt/planka" "planka-prebuild.zip"

msg_info "Setup planka"
msg_ok "Installed planka"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/planka.service
[Unit]
Description=planka Service
After=network.target

[Service]
WorkingDirectory=/opt/planka/
ExecStart=/opt/planka/.venv/bin/python3 planka.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now planka
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
