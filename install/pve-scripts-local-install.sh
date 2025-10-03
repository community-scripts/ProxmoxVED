#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE


source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
  $STD apt-get update
  $STD apt-get install -y \
    build-essential \
    git \
    sshpass \
    expect
msg_ok "Dependencies installed."

NODE_VERSION=22 setup_nodejs

INSTALL_DIR=${INSTALL_DIR:-/opt/PVESciptslocal}

if [ ! -d "$INSTALL_DIR/.git" ]; then
    msg_info "Cloning repository into $INSTALL_DIR..."
    $STD git clone https://github.com/michelroegl-brunner/PVESciptslocal.git "$INSTALL_DIR"
    msg_ok "Repository cloned."
else
    msg_info "Directory already exists. Pulling latest changes..."
    $STD git -C "$INSTALL_DIR" pull
    msg_ok "Repository updated."
fi

cd "$INSTALL_DIR"

msg_info "Installing PVE Scripts local"
$STD npm install
cp .env.example .env
mkdir -p data
chmod 755 data
$STD npm run build
msg_ok "Installed PVE Scripts local"

SERVICE_NAME="pvescriptslocal"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

msg_info "Creating Service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PVEScriptslocal Service
After=network.target

[Service]
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10
Environment=NODE_ENV=production
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now $SERVICE_NAME

msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean
msg_ok "Cleaned"

