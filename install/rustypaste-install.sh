#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

# Import Functions und Setup
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
  wget \
  sudo \
  git \
  mc \
  build-essential \
  ca-certificates
msg_ok "Dependencies Installed Successfully"

msg_info "Installing Rust"
RUST_VERSION="1.86.0" setup_rust
msg_ok "Rust Installed Successfully"

msg_info "Setting up ${APPLICATION}"
RELEASE=$(curl -s https://api.github.com/repos/orhun/rustypaste/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
# mv ${RELEASE}.tar.gz ${APPLICATION}.tar.gz
# tar -xzf ${APPLICATION}.tar.gz
cd /opt
git clone https://github.com/orhun/rustypaste.git
cd ${APPLICATION}
git fetch --tags
git checkout ${RELEASE}

cargo build --locked --release

echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setting up ${APPLICATION} is Done!"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
Environment="SERVER__ADDRESS=0.0.0.0:8000"

ExecStart=/opt/${APPLICATION}/target/release/rustypaste
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APPLICATION}.service
msg_ok "Created Service"

msg_ok "RustyPaste is Running!"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
