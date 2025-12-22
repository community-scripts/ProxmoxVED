#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os


msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  git \
  build-essential \
  ca-certificates
msg_ok "Dependencies Installed Successfully"

RUST_VERSION="1.92.0" setup_rust

msg_info "Setting up rustypaste"

fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "tarball" "latest" "/opt/rustypaste"

cd /opt/rustypaste

sed -i 's|^address = ".*"|address = "0.0.0.0:8000"|' config.toml

msg_info "Compiling rustypaste"
cargo build --locked --release

if [[ ! -f "/opt/rustypaste/target/release/rustypaste" ]]; then
    msg_error "Cargo build failed"
    exit
fi

msg_ok "Setting up rustypaste is Done!"

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

systemctl enable -q --now rustypaste.service
msg_ok "Created Service"

msg_ok "RustyPaste is Running!"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
