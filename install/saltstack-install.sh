#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/saltstack/salt

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  jq
msg_ok "Installed Dependencies"

msg_info "Installing Salt Master"
RELEASE=$(curl -fsSL https://api.github.com/repos/saltstack/salt/releases/latest | jq -r .tag_name | sed 's/^v//')
curl -fsSL "https://github.com/saltstack/salt/releases/download/v${RELEASE}/salt-master_${RELEASE}_amd64.deb" -o salt-master.deb
$STD dpkg -i salt-master.deb
systemctl enable -q --now salt-master
echo "${RELEASE_BARASSISTANT}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed Salt Master"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
rm salt-master.deb
msg_ok "Cleaned"
