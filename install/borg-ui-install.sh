#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/karanhudia/borg-ui

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3-dev \
  libffi-dev \
  libssl-dev \
  borgbackup \
  openssh-client
msg_ok "Installed Dependencies"

UV_PYTHON="3.12" setup_uv
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "borg-ui" "karanhudia/borg-ui" "tarball"

msg_info "Building Frontend"
cd /opt/borg-ui/frontend
$STD npm ci
$STD npm run build
mkdir -p /opt/borg-ui/app/static
cp -r /opt/borg-ui/frontend/build/* /opt/borg-ui/app/static/
msg_ok "Built Frontend"

msg_info "Setting up Python Environment"
cd /opt/borg-ui
$STD uv venv --python 3.12 /opt/borg-ui/.venv
$STD uv pip install --python /opt/borg-ui/.venv -r requirements.txt
msg_ok "Set up Python Environment"

msg_info "Configuring Borg-UI"
mkdir -p /opt/borg-ui_data
cat <<EOF >/opt/borg-ui/.env
PORT=8081
ENVIRONMENT=production
TZ=UTC
DATA_DIR=/opt/borg-ui_data
ENABLE_CRON_BACKUPS=true
ENABLE_STARTUP_LICENSE_SYNC=false
EOF
chmod 600 /opt/borg-ui/.env
msg_ok "Configured Borg-UI"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/borg-ui.service
[Unit]
Description=Borg-UI
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/borg-ui
EnvironmentFile=/opt/borg-ui/.env
ExecStart=/opt/borg-ui/.venv/bin/gunicorn app.main:app --bind 0.0.0.0:8081 --workers 2 --worker-class uvicorn.workers.UvicornWorker --timeout 300
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now borg-ui
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
