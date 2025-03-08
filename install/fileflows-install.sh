#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: kkroboth
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://fileflows.com/

# Import Functions und Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;sudo;mc)
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc
msg_ok "Installed Dependencies"

msg_info "Installing ASP.NET Core Runtime"
wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
$STD dpkg -i packages-microsoft-prod.deb
rm -rf packages-microsoft-prod.deb
$STD apt-get update
$STD apt-get install -y aspnetcore-runtime-8.0
msg_ok "Installed ASP.NET Core Runtime"

# Setup App
msg_info "Setup ${APPLICATION}"
temp_file=$(mktemp)
wget -q https://fileflows.com/downloads/zip -O $temp_file
unzip -q -d /opt/fileflows $temp_file
chmod +x /opt/fileflows/run-server.sh
msg_ok "Setup ${APPLICATION}"

# Creating Service
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
WorkingDirectory=/opt/wastebin
ExecStart=dotnet FileFlows.Server.dll
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APPLICATION}.service
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f $temp_file
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
