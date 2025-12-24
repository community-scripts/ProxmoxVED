#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Dependencies Installed Successfully"

RUST_VERSION="1.92.0" setup_rust
fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "tarball"

msg_info "Setting up rustypaste"
cd /opt/rustypaste
sed -i 's|^address = ".*"|address = "0.0.0.0:8000"|' config.toml
$STD cargo build --locked --release
msg_ok "Set up rustypaste"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rustypaste.service
[Unit]
Description=rustypaste Service
After=network.target

[Service]
WorkingDirectory=/opt/rustypaste
ExecStart=/opt/rustypaste/target/release/rustypaste
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rustypaste
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
