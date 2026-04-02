#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mauriceboe/TREK

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "trek" "mauriceboe/TREK" "tarball"

msg_info "Building Client"
cd /opt/trek/client
$STD npm ci
$STD npm run build
msg_ok "Built Client"

msg_info "Setting up Server"
cd /opt/trek/server
$STD npm ci
mkdir -p /opt/trek/server/public
cp -r /opt/trek/client/dist/* /opt/trek/server/public/
cp -r /opt/trek/client/public/fonts /opt/trek/server/public/fonts 2>/dev/null || true
mkdir -p /opt/trek/{data/logs,uploads/{files,covers,avatars,photos}}
ln -sf /opt/trek/data /opt/trek/server/data
ln -sf /opt/trek/uploads /opt/trek/server/uploads
ENCRYPTION_KEY=$(openssl rand -hex 32)
cat <<EOF >/opt/trek/server/.env
NODE_ENV=production
PORT=3000
ENCRYPTION_KEY=${ENCRYPTION_KEY}
COOKIE_SECURE=false
FORCE_HTTPS=false
LOG_LEVEL=info
TZ=UTC
EOF
msg_ok "Set up Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/trek.service
[Unit]
Description=TREK Travel Planner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/trek/server
EnvironmentFile=/opt/trek/server/.env
ExecStart=/usr/bin/node --import tsx src/index.ts
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now trek
msg_ok "Created Service"

msg_info "Waiting for initial setup"
for i in $(seq 1 15); do
  if journalctl -u trek --no-pager -q 2>/dev/null | grep -q "Admin Account Created"; then
    TREK_PW=$(journalctl -u trek --no-pager -q 2>/dev/null | grep "Password:" | tail -1 | sed 's/.*Password: *//;s/ *║.*//')
    TREK_EMAIL=$(journalctl -u trek --no-pager -q 2>/dev/null | grep "Email:" | tail -1 | sed 's/.*Email: *//;s/ *║.*//')
    break
  fi
  sleep 1
done
msg_ok "Initial setup complete"

if [[ -n "${TREK_PW:-}" ]]; then
  {
    echo ""
    echo "TREK Admin Credentials"
    echo "Email:    ${TREK_EMAIL}"
    echo "Password: ${TREK_PW}"
    echo "(Change password after first login)"
    echo ""
  } >>~/trek.creds
fi

motd_ssh
customize
cleanup_lxc
