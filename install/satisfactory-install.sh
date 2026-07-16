#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: n8flx
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.satisfactorygame.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  lib32gcc-s1 \
  lib32stdc++6
msg_ok "Installed Dependencies"

msg_info "Creating Application Directories"
mkdir -p /opt/satisfactory/server
msg_ok "Created Application Directories"

fetch_and_deploy_from_url \
  "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
  "/opt/steamcmd"

msg_info "Installing Satisfactory Dedicated Server"
$STD /opt/steamcmd/steamcmd.sh \
  +force_install_dir /opt/satisfactory/server \
  +login anonymous \
  +app_update 1690800 -beta public validate \
  +quit
msg_ok "Installed Satisfactory Dedicated Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/satisfactory.service
[Unit]
Description=Satisfactory Dedicated Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/satisfactory/server
Environment=LANG=C.UTF-8
ExecStart=/opt/satisfactory/server/FactoryServer.sh -log
Restart=on-failure
RestartSec=10
KillSignal=SIGINT
TimeoutStopSec=120
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now satisfactory
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
