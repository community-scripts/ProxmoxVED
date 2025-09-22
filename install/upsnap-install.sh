#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/seriousm4x/UpSnap

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  nmap \
  samba \
  samba-common-bin \
  openssh-client \
  openssh-server \
  sshpass
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "upsnap" "seriousm4x/UpSnap" "prebuild" "latest" "/opt/upsnap" "UpSnap_*_linux_amd64.zip"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/upsnap.service
[Unit]
Description=UpSnap Service
Documentation=https://github.com/seriousm4x/UpSnap/wiki
After=network.target

[Service]
Type=simple
Restart=on-failure
WorkingDirectory=/opt/upsnap
ExecStart=/opt/upsnap/upsnap serve --http=0.0.0.0:8090

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now upsnap
msg_ok "Service Created"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
