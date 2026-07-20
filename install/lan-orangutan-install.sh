#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stefan Knaak (corgan2222)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/291-Group/LAN-Orangutan

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nmap
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "lan-orangutan" "291-Group/LAN-Orangutan" "prebuild" "latest" "/opt/lan-orangutan" "orangutan-linux-$(arch_resolve).tar.gz"

msg_info "Configuring LAN-Orangutan"
mv "/opt/lan-orangutan/orangutan-linux-$(arch_resolve)" /opt/lan-orangutan/orangutan
chmod +x /opt/lan-orangutan/orangutan
ln -sf /opt/lan-orangutan/orangutan /usr/local/bin/orangutan
mkdir -p /etc/lan-orangutan /var/lib/lan-orangutan
cat <<EOF >/etc/lan-orangutan/config.ini
[server]
port = 291
bind_address = 0.0.0.0
enable_api = true

[scanning]
scan_interval = 300
min_scan_interval = 30
enable_port_scan = false
port_scan_range = 1-1024

[storage]
max_devices = 1000
retention_days = 90

[tailscale]
enable = true
auto_detect = true

[ui]
theme = auto
EOF
msg_ok "Configured LAN-Orangutan"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/lan-orangutan.service
[Unit]
Description=LAN Orangutan Network Scanner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lan-orangutan
ExecStart=/opt/lan-orangutan/orangutan serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now lan-orangutan
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
