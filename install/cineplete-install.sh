#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: sdblepas
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/sdblepas/CinePlete

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y python3
msg_ok "Installed Dependencies"

UV_PYTHON="3.12" setup_uv
fetch_and_deploy_gh_release "cineplete" "sdblepas/CinePlete" "tarball"

msg_info "Setting up ${APP}"
mkdir -p /data /config
cd /opt/cineplete
$STD uv venv --clear .venv --python=python3
$STD uv pip install -r requirements.txt --python .venv/bin/python
msg_ok "Set up ${APP}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/cineplete.service
[Unit]
Description=CinePlete — Movie library gap finder
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cineplete
Environment=DATA_DIR=/data
Environment=CONFIG_DIR=/config
Environment=STATIC_DIR=/opt/cineplete/static
ExecStart=/opt/cineplete/.venv/bin/uvicorn app.web:app --host 0.0.0.0 --port 7474 --workers 1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now cineplete
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
