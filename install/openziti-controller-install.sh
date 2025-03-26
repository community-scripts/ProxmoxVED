#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: emoscardini
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/openziti/ziti

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y gpg
msg_ok "Installed Dependencies"

msg_info "Installing openziti"
mkdir -p --mode=0755 /usr/share/keyrings
curl -sSLf https://get.openziti.io/tun/package-repos.gpg | gpg --dearmor -o /usr/share/keyrings/openziti.gpg
echo "deb [signed-by=/usr/share/keyrings/openziti.gpg] https://packages.openziti.org/zitipax-openziti-deb-stable debian main" > /etc/apt/sources.list.d/openziti.list
$STD apt-get update 
$STD apt-get install -y openziti-controller openziti-console
msg_ok "Installed openziti"

read -r -p "Would you like to go through the auto configuration now? <y/N>" prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Starting Configuration"
  bash /opt/openziti/etc/controller/bootstrap.bash
  msg_ok "Configuration Completed"
  systemctl enable -q --now ziti-controller
else
  systemctl enable -q ziti-controller
  msg_err "Configration not provided; Please run /opt/openziti/etc/controller/bootstrap.bash to configure the controller and restart the container"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
