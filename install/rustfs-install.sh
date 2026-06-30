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

msg_info "Installing RustFS"
ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" == "amd64" ]]; then
  RUSTFS_ARCH="x86_64"
elif [[ "$ARCH" == "arm64" ]]; then
  RUSTFS_ARCH="aarch64"
else
  msg_error "Unsupported architecture: $ARCH"
  exit 1
fi

mkdir -p /opt/rustfs
cd /opt/rustfs || exit
RELEASE=$(curl -sL https://api.github.com/repos/rustfs/rustfs/releases | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -z "$RELEASE" ]]; then
  msg_error "Failed to fetch latest release version"
  exit 1
fi
wget -q "https://github.com/rustfs/rustfs/releases/download/${RELEASE}/rustfs-linux-${RUSTFS_ARCH}-gnu-latest.zip"
unzip -q rustfs-linux-${RUSTFS_ARCH}-gnu-latest.zip
rm rustfs-linux-${RUSTFS_ARCH}-gnu-latest.zip
chmod +x rustfs
msg_ok "Installed RustFS ${RELEASE}"

msg_info "Configuring RustFS"
mkdir -p /opt/rustfs/data /opt/rustfs/logs
RUSTFS_ROOT_USER=rustfsadmin
RUSTFS_ROOT_PASSWORD=rustfsadmin
cat <<EOF >/opt/rustfs/.env
RUSTFS_ROOT_USER=${RUSTFS_ROOT_USER}
RUSTFS_ROOT_PASSWORD=${RUSTFS_ROOT_PASSWORD}
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
ExecStart=/opt/rustfs/rustfs server /opt/rustfs/data --console-address :9001
Restart=on-failure
RestartSec=5
StandardOutput=append:/opt/rustfs/logs/rustfs.log
StandardError=append:/opt/rustfs/logs/rustfs.log

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now rustfs
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
