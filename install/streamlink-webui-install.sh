#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/CrazyWolf13/streamlink-webui

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setup NodeJS"
NODE_VERSION="22"
NODE_MODULE="npm@latest,yarn@latest"
install_node_and_modules
msg_ok "Setup NodeJS"

msg_info "Setup Python"
setup_uv
msg_ok "Setup Python"

msg_info "Setup ${APPLICATION}"
fetch_and_deploy_gh_release "CrazyWolf13/streamlink-webui"
$STD uv venv /opt/**/backend/src/.venv
source /opt/**/.venv/bin/activate
$STD uv sync --all-extras
$STD pip install -r requirements.txt
cd ../../frontend/src
$STD yarn build
msg_ok "Setup ${APPLICATION}"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<'EOF' >/opt/"${APPLICATION}".env
CLIENT_ID='your_client_id'
CLIENT_SECRET='your_client_secret'
DOWNLOAD_PATH=/opt/streamlink-webui-download'
# BASE_URL='https://sub.domain.com' \
# REVERSE_PROXY=True \
EOF

cat <<EOF >/etc/systemd/system/"${APPLICATION}".service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
EnvironmentFile=/opt/${APPLICATION}.env
WorkingDirectory=/opt/${APPLICATION}/backend/src
ExecStart=fastapi run main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now "${APPLICATION}"
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f "${RELEASE}".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
