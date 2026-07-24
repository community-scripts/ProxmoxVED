#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/EpicGames/lore

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "lore" "EpicGames/lore" "prebuild" "latest" "/opt/lore" "loreserver-*-x86_64-unknown-linux-gnu.tar.gz"

msg_info "Generating Self-Signed Certificate"
create_self_signed_cert "lore"
msg_ok "Generated Self-Signed Certificate"

msg_info "Setting up Lore Server"
chmod +x /opt/lore/loreserver
mkdir -p /opt/lore/store
cat <<EOF >/opt/lore/local.toml
[server.quic]
host = "0.0.0.0"
port = 41337

[server.quic.certificate]
cert_file = "/etc/ssl/lore/lore.crt"
pkey_file = "/etc/ssl/lore/lore.key"

[immutable_store.local]
path = "/opt/lore/store"
flush_delay_seconds = 10

[mutable_store.local]
path = "/opt/lore/store"
flush_delay_seconds = 10
EOF
msg_ok "Set up Lore Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/lore.service
[Unit]
Description=Lore Version Control Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lore
ExecStart=/opt/lore/loreserver --config /opt/lore
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now lore
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
