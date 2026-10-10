#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/figranium/figranium

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  xvfb \
  x11vnc \
  websockify
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

# Figranium serves the viewer from /opt/novnc; Debian's novnc package depends on Debian's nodejs
fetch_and_deploy_gh_release "novnc" "novnc/noVNC" "tarball" "latest" "/opt/novnc"
fetch_and_deploy_gh_release "figranium" "figranium/figranium" "tarball"

msg_info "Building Figranium"
cd /opt/figranium
# postinstall would otherwise download every Playwright browser; only Chromium is used
export FIGRANIUM_SKIP_PLAYWRIGHT_INSTALL=1
$STD npm ci --include=dev
$STD npm run build
$STD npm prune --omit=dev
# Data and capture paths are fixed relative to the app; linked only after the build, as Vite copies public/ into dist/
mkdir -p /opt/figranium_data/{data,captures} /opt/figranium/src/public
ln -s /opt/figranium_data/data /opt/figranium/data
ln -s /opt/figranium_data/captures /opt/figranium/public/captures
ln -s /opt/figranium_data/captures /opt/figranium/src/public/captures
msg_ok "Built Figranium"

msg_info "Installing Chromium for Figranium"
$STD npx playwright install --with-deps chromium
msg_ok "Installed Chromium for Figranium"

msg_info "Configuring Figranium"
cat <<EOF >/opt/figranium_data/.env
NODE_ENV=production
PORT=11345
FIGRANIUM_TELEMETRY_ENABLED=false
EOF
cat <<EOF >/opt/figranium_data/data/vnc_password.txt
$(random_password 16)
EOF
chmod 600 /opt/figranium_data/.env /opt/figranium_data/data/vnc_password.txt
msg_ok "Configured Figranium"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/figranium-xvfb.service
[Unit]
Description=Figranium Virtual Display
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/rm -f /tmp/.X99-lock
ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/figranium-vnc.service
[Unit]
Description=Figranium VNC Server
After=figranium-xvfb.service
Requires=figranium-xvfb.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :99 -forever -shared -localhost -rfbport 5900 -passwdfile /opt/figranium_data/data/vnc_password.txt -wait 20 -defer 30
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/figranium-novnc.service
[Unit]
Description=Figranium noVNC Proxy
After=figranium-vnc.service

[Service]
Type=simple
ExecStart=/usr/bin/websockify 127.0.0.1:54311 127.0.0.1:5900
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/figranium.service
[Unit]
Description=Figranium
After=network.target figranium-xvfb.service figranium-novnc.service
Wants=figranium-xvfb.service figranium-vnc.service figranium-novnc.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/figranium
EnvironmentFile=/opt/figranium_data/.env
Environment=DISPLAY=:99
ExecStart=/usr/bin/node /opt/figranium/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now figranium-xvfb figranium-vnc figranium-novnc figranium
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
