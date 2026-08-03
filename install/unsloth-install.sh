#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/unslothai/unsloth

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
  libgomp1 \
  git
msg_ok "Installed Dependencies"

UV_PYTHON="3.12" setup_uv

msg_info "Setting up Unsloth Studio (Patience)"
mkdir -p /opt/unsloth_data
$STD uv venv --python 3.12 /opt/unsloth/.venv
$STD uv pip install --python /opt/unsloth/.venv --torch-backend=auto unsloth-zoo unsloth
msg_ok "Set up Unsloth Studio"

msg_info "Configuring Unsloth Studio"
UNSLOTH_PASSWORD=$(openssl rand -base64 18)
cat <<EOF >/opt/unsloth.env
UNSLOTH_STUDIO_PASSWORD=${UNSLOTH_PASSWORD}
UNSLOTH_STUDIO_HOME=/opt/unsloth_data
HF_HOME=/opt/unsloth_data/huggingface
EOF
chmod 600 /opt/unsloth.env
msg_ok "Configured Unsloth Studio"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/unsloth.service
[Unit]
Description=Unsloth Studio
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/unsloth_data
EnvironmentFile=/opt/unsloth.env
ExecStart=/opt/unsloth/.venv/bin/unsloth studio -H 0.0.0.0 -p 8888
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now unsloth
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
