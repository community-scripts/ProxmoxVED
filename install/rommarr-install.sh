#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BlizzHacker
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/BlizzHacker/rommarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y python3-venv
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "rommarr" "BlizzHacker/rommarr" "tarball" "latest" "/opt/rommarr"

msg_info "Setting up Rommarr"
cd /opt/rommarr
$STD python3 -m venv .venv
$STD /opt/rommarr/.venv/bin/pip install --upgrade pip
$STD /opt/rommarr/.venv/bin/pip install -r requirements.txt

# Rommarr talks to three services and stores nothing else. Every value here is
# a placeholder on purpose: it starts and serves its UI with none of them
# reachable, and the Settings pages say which are missing, so a first run is
# never a blank failure.
cat <<EOF >/opt/rommarr/.env
PROWLARR_URL=http://192.168.1.100:9696
PROWLARR_API_KEY=

QBITTORRENT_URL=http://192.168.1.100:8080
QBITTORRENT_USER=admin
QBITTORRENT_PASS=

ROMM_URL=http://192.168.1.100:8080
ROMM_USERNAME=
ROMM_PASSWORD=

# Where imported ROMs are filed. This must be a path RomM also scans, or the
# import succeeds and the game never appears.
ROMM_LIBRARY=/mnt/roms
ROMMARR_DATA=/opt/rommarr/rommarr.json
ROMMARR_PORT=7878
LOG_LEVEL=INFO
EOF
chmod 600 /opt/rommarr/.env
mkdir -p /mnt/roms
msg_ok "Set up Rommarr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rommarr.service
[Unit]
Description=Rommarr - the *arr for games
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/rommarr
EnvironmentFile=/opt/rommarr/.env
ExecStart=/opt/rommarr/.venv/bin/python -m rommarr
Restart=on-failure
RestartSec=10

# It reads indexers and writes ROMs into one directory; nothing else on the
# filesystem is any of its business.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/rommarr /mnt/roms

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rommarr
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
