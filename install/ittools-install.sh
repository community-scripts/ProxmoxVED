#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: sorash (sorash)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/CorentinTh/it-tools/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setup Docker Repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
$STD apt-get update
msg_ok "Setup Docker Repository"

msg_info "Installing Docker"
$STD apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
msg_ok "Installed Docker"

msg_info "Installing IT Tools"
mkdir -p /opt/ittools
cat <<EOF >/opt/ittools/compose.yaml
version: "3"
services:
  ittools:
    image: corentinth/it-tools:latest
    container_name: ittools
    restart: unless-stopped
    ports:
      - 80:80
EOF
cd /opt/ittools
$STD docker compose up -d
msg_ok "Installed IT Tools"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
