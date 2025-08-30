#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: EEJoshua
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/overleaf/toolkit

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git ca-certificates curl gnupg
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list
$STD apt-get update
$STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
$STD systemctl enable --now docker
msg_ok "Installed Dependencies"

msg_info "Setup Overleaf"
install -d -m 0755 /opt
if [[ -d /opt/overleaf-toolkit/.git ]]; then
  $STD git -C /opt/overleaf-toolkit pull -q
else
  $STD git clone -q https://github.com/overleaf/toolkit.git /opt/overleaf-toolkit
fi
cd /opt/overleaf-toolkit
$STD bin/init </dev/null

CFG="config/overleaf.rc"
grep -q '^OVERLEAF_LISTEN_IP=' "$CFG" \
  && sed -i 's/^OVERLEAF_LISTEN_IP=.*/OVERLEAF_LISTEN_IP=0.0.0.0/' "$CFG" \
  || echo 'OVERLEAF_LISTEN_IP=0.0.0.0' >> "$CFG"

grep -q '^SIBLING_CONTAINERS_ENABLED=' "$CFG" \
  && sed -i 's/^SIBLING_CONTAINERS_ENABLED=.*/SIBLING_CONTAINERS_ENABLED=false/' "$CFG" \
  || echo 'SIBLING_CONTAINERS_ENABLED=false' >> "$CFG"
msg_ok "Setup Overleaf"

msg_info "Starting Overleaf"
$STD bin/up -d

msg_ok "Started Overleaf"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
