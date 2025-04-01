#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Don Locke (DonLocke)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/AllStarLink

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Adding ASL Package Repository"
wget -q -P /tmp https://repo.allstarlink.org/public/asl-apt-repos.deb12_all.deb
$STD dpkg -i /tmp/asl-apt-repos.deb12_all.deb
$STD apt-get update
msg_ok "Added ASL Package Repository"

msg_info "Installing AllStarLink"
$STD apt-get install -y asl3
msg_ok "Installed AllStarLink"

msg_info "Configuring AllStarLink"
sed -i "/secret /s/= .*/= $(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)/" /etc/asterisk/manager.conf
msg_ok "Configured AllStarLink"

read -r -p "Would you like to set up AllStarLink Node now? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  node-setup
else
  msg_warn "You will need to run \`node-setup\` before you can connect to the AllStarLink Network."
fi

read -r -p "Would you like to add Allmon3? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Installing Allmon3"
  $STD apt-get install -y allmon3
  msg_ok "Installed Allmon3"

  NODE=$(grep -oP '^\[\d+\]\(node-main\)' /etc/asterisk/rpt.conf | grep -oP '\d+')
  if [[ -n $NODE ]]; then
    msg_info "Configuring Allmon3"
    sed -i "s/;\[1999\]/\[$NODE\]/" /etc/allmon3/allmon3.ini
    sed -i "s/;host/host/" /etc/allmon3/allmon3.ini
    sed -i "s/;user/user/" /etc/allmon3/allmon3.ini
    sed -i "s/;pass=.*/pass=$(sed -ne 's/^secret = //p' /etc/asterisk/manager.conf)/" /etc/allmon3/allmon3.ini
    systemctl restart allmon3
    msg_ok "Configured Allmon3"
  fi
fi

motd_ssh
customize

msg_info "Cleaning up"
rm -f /tmp/asl-apt-repos.deb12_all.deb
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
