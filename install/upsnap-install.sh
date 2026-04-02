#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/seriousm4x/UpSnap

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nmap \
  smbclient \
  sshpass \
  libcap2-bin
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "upsnap" "seriousm4x/UpSnap" "prebuild" "latest" "/opt/upsnap" "UpSnap_*_linux_amd64.zip"

msg_info "Setting up Application"
chmod +x /opt/upsnap/upsnap
setcap 'cap_net_raw=+ep' /opt/upsnap/upsnap
msg_ok "Set up Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/upsnap.service
[Unit]
Description=UpSnap Wake-on-LAN
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/upsnap
ExecStart=/opt/upsnap/upsnap serve --http 0.0.0.0:8090
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now upsnap
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
