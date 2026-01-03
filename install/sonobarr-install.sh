#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Dodelidoo-Labs/sonobarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "sonobarr" "Dodelidoo-Labs/sonobarr" "tarball"

msg_info "Setting up sonobarr"

cd /opt/sonobarr

python3 -m venv venv

source venv/bin/activate

pip install --no-cache-dir -r requirements.txt
msg_ok "Set up sonobarr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/sonobarr
[Unit]
Description=sonobarr Service
After=network.target

[Service]
WorkingDirectory=/opt/sonobarr
ExecStart=/bin/bash -c 'gunicorn src.Sonobarr:app -c gunicorn_config.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now sonobarr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
