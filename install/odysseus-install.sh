#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Indigo (alexindigo)
# License: MIT | https://github.com/alexindigo/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus | https://pewdiepie-archdaemon.github.io/odysseus/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  tmux
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

msg_info "Cloning Odysseus"
$STD git clone https://github.com/pewdiepie-archdaemon/odysseus.git /opt/odysseus
$STD git -C /opt/odysseus checkout main
msg_ok "Cloned Odysseus"

msg_info "Setting up Python Environment"
cd /opt/odysseus
$STD uv venv /opt/odysseus/venv
$STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python
msg_ok "Set up Python Environment"

msg_info "Running Setup"
cd /opt/odysseus
ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
export ODYSSEUS_ADMIN_USER="admin"
export ODYSSEUS_ADMIN_PASSWORD="$ADMIN_PASS"
/opt/odysseus/venv/bin/python /opt/odysseus/setup.py
msg_ok "Setup Complete"
echo -e "${INFO}${YW} Admin Username: admin${CL}"
echo -e "${INFO}${YW} Admin Password: ${ADMIN_PASS}${CL}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/odysseus.service
[Unit]
Description=Odysseus AI Workspace
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/odysseus
Environment=PATH=/opt/odysseus/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/odysseus/venv/bin/uvicorn app:app --host 0.0.0.0 --port 80
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now odysseus
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
