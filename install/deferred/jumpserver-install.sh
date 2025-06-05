#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Nícolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/jumpserver/jumpserver

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  iptables
msg_ok "Installed Dependencies"

msg_info "Installing JumpServer"
cd /opt
RELEASE=$(curl -fsSL https://api.github.com/repos/jumpserver/installer/releases/latest | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
curl -fsSL "https://github.com/jumpserver/installer/releases/download/${RELEASE}/jumpserver-installer-${RELEASE}.tar.gz" -o jumpserver-installer-${RELEASE}.tar.gz
mkdir -p /opt/jumpserver
tar -xzvf jumpserver-installer-${RELEASE}.tar.gz -C /opt/jumpserver --strip-components=1
cd /opt/jumpserver
$STD ./jmsctl.sh install <<EOF
n
n
n
redis
n
n
EOF
$STD ./jmsctl.sh start
echo "${RELEASE}" >/opt/${APP}_version.txt
msg_ok "Installed JumpServer"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/jumpserver-installer-${RELEASE}.tar.gz
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
