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
$STD apt-get install -y \
    ffmpeg \
    jq
msg_ok "Installed Dependencies"

msg_info "Installing ConvertX"
curl -fsSL "https://bun.sh/install" | bash
ln -sf /root/.bun/bin/bun /usr/local/bin/bun
mkdir -p /opt/convertx

RELEASE=$(curl -fsSL https://api.github.com/repos/C4illin/ConvertX/releases/latest | jq -r .tag_name | sed 's/^v//')
curl -fsSL -o "/opt/convertx/ConvertX-${RELEASE}.tar.gz" "https://github.com/C4illin/ConvertX/archive/refs/tags/v${RELEASE}.tar.gz"
tar --strip-components=1 -xf "/opt/convertx/ConvertX-${RELEASE}.tar.gz" -C /opt/convertx
cd /opt/convertx
mkdir -p data
bun install

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
systemctl enable -q --now convertx
msg_ok "Service Created"

msg_info "Waiting for SQLite database"
for ((COUNT=0; COUNT<60; COUNT++)); do
  [ -f "/opt/convertx/data/mydb.sqlite" ] && { systemctl restart convertx; exit 0; }
  sleep 0.5
done
msg_error "Timed out waiting for database!"
exit 1
msg_ok "Database created"

motd_ssh
customize

msg_info "Cleaning up"
$STD rm -f /opt/ConvertX-${RELEASE}.tar.gz
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
