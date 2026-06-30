#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rustfs/rustfs

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "rustfs" "rustfs/rustfs" "prebuild" "latest" "/opt/rustfs" "rustfs-linux-$(dpkg --print-architecture).tar.gz"

msg_info "Configuring RustFS"
mkdir -p /opt/rustfs/data /opt/rustfs/logs
RUSTFS_ROOT_USER=$(tr -d '-' </proc/sys/kernel/random/uuid | cut -c1-16)
RUSTFS_ROOT_PASSWORD=$(tr -d '-' </proc/sys/kernel/random/uuid)
cat <<EOF >/opt/rustfs/.env
RUSTFS_ROOT_USER=${RUSTFS_ROOT_USER}
RUSTFS_ROOT_PASSWORD=${RUSTFS_ROOT_PASSWORD}
RUSTFS_VOLUMES=/opt/rustfs/data
RUSTFS_OPTS="--console-address :9001"
EOF
chmod 0600 /opt/rustfs/.env
msg_ok "Configured RustFS"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rustfs.service
[Unit]
Description=RustFS Object Storage
Documentation=https://docs.rustfs.com/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rustfs
EnvironmentFile=/opt/rustfs/.env
ExecStart=/opt/rustfs/rustfs server \$RUSTFS_VOLUMES \$RUSTFS_OPTS
Restart=on-failure
RestartSec=5
StandardOutput=append:/opt/rustfs/logs/rustfs.log
StandardError=append:/opt/rustfs/logs/rustfs.log

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rustfs
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
