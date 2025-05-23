#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/C4illin/ConvertX

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git curl ffmpeg
msg_ok "Installed Dependencies"

msg_info "Installing ConvertX"
$STD curl -fsSL "https://bun.sh/install" | bash
$STD ln -sf /root/.bun/bin/bun /usr/local/bin/bun
$STD git clone "https://github.com/C4illin/ConvertX.git" /opt/convertx
$STD cd /opt/convertx && bun install

JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
cat <<EOF >/opt/convertx/.env
JWT_SECRET=$JWT_SECRET
HTTP_ALLOWED=true
PORT=3000
EOF
msg_ok "Installed ConvertX"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/convertx.service
[Unit]
Description=ConvertX File Converter
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/convertx
EnvironmentFile=/opt/convertx/.env
ExecStart=/root/.bun/bin/bun dev
Restart=always

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Service Created"

msg_info "Waiting for SQLite database to be created"
TIMEOUT=60
COUNT=0
while [[ ! -f "/opt/convertx/data/mydb.sqlite" && $COUNT -lt $TIMEOUT ]]; do
    sleep 0.5
    COUNT=$((COUNT + 1))
done
if [[ -f "/opt/convertx/data/mydb.sqlite" ]]; then
    systemctl enable -q --now convertx
else
    msg_error "Timed out waiting for /opt/convertx/data/mydb.sqlite to be created!"
    exit 1
fi
msg_ok "Database Created"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
