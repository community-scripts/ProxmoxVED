#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tomfrenzel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rustmailer/bichon

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Creating directories"
$STD mkdir -p /opt/bichon /opt/bichon-data
msg_ok "Created directories"

fetch_and_deploy_gh_release "bichon" "rustmailer/bichon" "prebuild" "latest" "/opt/bichon" "bichon-*-x86_64-unknown-linux-gnu.tar.gz"

msg_info "Configuring Bichon"
cat <<EOF >/opt/bichon/.env
BICHON_ROOT_DIR=/opt/bichon-data
BICHON_ENCRYPT_PASSWORD=$(openssl rand -base64 32)
EOF
msg_ok "Configured Bichon"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/bichon.service
[Unit]
Description=Bichon server
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/opt/bichon/.env
ExecStart=/opt/bichon/bichon
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bichon
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
