#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Fabien Penso (penso)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/moltis-org/moltis

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ARCH=$(dpkg --print-architecture)
RELEASE=$(curl -fsSL https://api.github.com/repos/moltis-org/moltis/releases/latest | grep "tag_name" | awk -F '"' '{print $4}')

msg_info "Installing Moltis ${RELEASE}"
curl -fsSL -o /tmp/moltis.deb "https://github.com/moltis-org/moltis/releases/download/${RELEASE}/moltis_${RELEASE}_${ARCH}.deb"
$STD dpkg -i /tmp/moltis.deb
rm -f /tmp/moltis.deb
msg_ok "Installed Moltis ${RELEASE}"

msg_info "Configuring Moltis"
useradd -r -s /usr/sbin/nologin -d /var/lib/moltis moltis
mkdir -p /var/lib/moltis /etc/moltis
chown moltis:moltis /var/lib/moltis /etc/moltis
msg_ok "Configured Moltis"

read -r -p "${TAB3}Would you like to install Docker for sandbox support? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Installing Docker"
  $STD sh <(curl -fsSL https://get.docker.com)
  $STD usermod -aG docker moltis
  msg_ok "Installed Docker"
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/moltis.service
[Unit]
Description=Moltis Agent Server
After=network-online.target
Wants=network-online.target
Documentation=https://docs.moltis.org

[Service]
Type=simple
User=moltis
Group=moltis
ExecStart=/usr/bin/moltis serve --bind 0.0.0.0
Restart=on-failure
RestartSec=5
Environment=MOLTIS_DATA_DIR=/var/lib/moltis
Environment=MOLTIS_CONFIG_DIR=/etc/moltis
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/moltis /etc/moltis
PrivateTmp=true
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now moltis
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
