#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Dictionarry-Hub/profilarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  python3-dev \
  libffi-dev \
  libssl-dev 
msg_ok "Installed Dependencies"

UV_VERSION="0.7.19" PYTHON_VERSION="3.12" setup_uv
NODE_VERSION="22" setup_nodejs

msg_info "Creating directories"
mkdir -p /opt/profilarr \
  /opt/profilarr/data
msg_ok "Created directories"

fetch_and_deploy_gh_release "profilarr" "Dictionarry-Hub/profilarr"

msg_info "Installing Python Dependencies"
cd /opt/profilarr
export UV_CONCURRENT_DOWNLOADS=1
$STD uv sync --no-dev --frozen
msg_ok "Installed Python Dependencies"

msg_info "Building Frontend"
if [[ -d /opt/profilarr/frontend ]]; then
  cd /opt/profilarr/frontend
  $STD npm install
  $STD npm run build
  msg_ok "Built Frontend"
else
  msg_ok "No frontend directory found, skipping frontend build"
fi

msg_info "Creating Service"
cat <<EOF >/opt/profilarr.env
PROFILARR_HOST=0.0.0.0
PROFILARR_PORT=6868
PROFILARR_DATA_DIR=/opt/profilarr/data
PYTHONUNBUFFERED=1
EOF
cat <<EOF >/etc/systemd/system/profilarr.service
[Unit]
Description=Profilarr - Configuration Management Platform for Radarr/Sonarr
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/profilarr
EnvironmentFile=/opt/profilarr.env
Environment="PATH=/opt/profilarr/.venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/opt/profilarr/.venv/bin/python -m profilarr
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now profilarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

