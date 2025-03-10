#!/usr/bin/env bash

# Copyright (c) 2021-2024 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE
# Source: https://github.com/hudikhq/hoodik

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  pkg-config \
  libssl-dev \
  libc6-dev \
  libpq-dev \
  clang \
  llvm \
  nettle-dev \
  build-essential \
  curl \
  sudo \
  make \
  mc
msg_ok "Installed Dependencies"

msg_info "Installing Rust (Patience)"
$STD bash <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs) -y
source ~/.cargo/env
msg_ok "Installed Rust"

msg_info "Installing Hoodik (Patience)"
cd /opt
RELEASE=$(curl -s https://api.github.com/repos/hudikhq/hoodik/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/hudikhq/hoodik/archive/refs/tags/${RELEASE}.zip"
unzip -q ${RELEASE}.zip
mv "hoodik-${RELEASE:1}" hoodik
cd hoodik
cargo build -q --release
msg_ok "Installed hoodik"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/hoodik.service
[Unit]
Description=Start Hoodik Service
After=network.target

[Service]
User=root
WorkingDirectory=/opt/hoodik
ExecStart=/root/.cargo/bin/cargo run -q --release

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hoodik.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/${RELEASE}.zip
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
