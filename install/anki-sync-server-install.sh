#!/usr/bin/env bash

# Copyright (c) community-scripts ORG
# Author: EsBaTix
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.ankiweb.net/sync-server.html

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  python3 \
  python3-pip \
  python3-venv
msg_ok "Installed Dependencies"

msg_info "Creating Anki User"
useradd -m -s /bin/bash anki
msg_ok "Created Anki User"

msg_info "Installing Anki"
mkdir -p /opt/anki/
mkdir -p /opt/anki/syncbase
cat <<EOF >/opt/anki/.env
SYNC_BASE=/opt/anki/syncbase
SYNC_USER1=sync:sync
EOF
chown -R anki:anki /opt/anki/
$STD runuser -u anki -- \
  python3 -m venv /opt/anki/venv && \
  /opt/anki/venv/bin/pip install anki
msg_ok "Installed Anki"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/anki-sync-server.service
[Unit]
Description=Anki Sync Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
UMask=0077
ExecStart=/opt/anki/venv/bin/python -m anki.syncserver
Restart=on-failure
RestartSec=5
ProtectProc=invisible
ProcSubset=pid
User=anki
Group=anki
EnvironmentFile=/opt/anki/.env
WorkingDirectory=/opt/anki

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now anki-sync-server
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc