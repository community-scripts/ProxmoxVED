#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: KellanStevens
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Stremio/stremio-service

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  jq \
  ca-certificates \
  wget \
  build-essential
msg_ok "Installed Dependencies"

# Install Node.js 14
msg_info "Installing Node.js 14"
NODEJS_FORCE_YES=1 curl -fsSL https://deb.nodesource.com/setup_14.x | bash -
$STD apt-get install -y nodejs
msg_ok "Installed Node.js 14"

# Install Jellyfin FFmpeg
msg_info "Installing Jellyfin FFmpeg"
wget -q https://repo.jellyfin.org/archive/ffmpeg/debian/4.4.1-4/jellyfin-ffmpeg_4.4.1-4-buster_amd64.deb -O /tmp/jellyfin-ffmpeg.deb
$STD apt-get install -y /tmp/jellyfin-ffmpeg.deb
rm /tmp/jellyfin-ffmpeg.deb
msg_ok "Installed Jellyfin FFmpeg"

# Setup Stremio Server
msg_info "Setup stremio-server"
mkdir -p /opt/stremio-server
cd /opt/stremio-server || exit

# Download the latest server.js file
BUILD="desktop"
VERSION="master"
SERVER_URL="https://dl.strem.io/server/${VERSION}/${BUILD}/server.js"

if command -v curl >/dev/null 2>&1; then
  curl --fail -O "$SERVER_URL"
elif command -v wget >/dev/null 2>&1; then
  wget "$SERVER_URL"
else
  msg_info "No curl or wget found, installing curl"
  $STD apt-get install -y curl
  curl --fail -O "$SERVER_URL"
fi

echo "${RELEASE}" >/opt/"stremio-server"_version.txt
msg_ok "Setup stremio-server"

# Creating Service
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/"stremio-server".service
[Unit]
Description=stremio-server Service
After=network.target

[Service]
WorkingDirectory=/opt/stremio-server
ExecStart=/usr/bin/node /opt/stremio-server/server.js
Restart=always
User=root
Environment=CASTING_DISABLED=1

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now "stremio-server"
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
