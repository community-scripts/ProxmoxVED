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
  git \
  build-essential \
  ca-certificates
msg_ok "Dependencies Installed Successfully"

setup_rust

msg_info "Setting up ${APPLICATION}"
# Getting the latest release version
RELEASE=$(curl -s https://api.github.com/repos/orhun/rustypaste/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
cd /opt
git clone https://github.com/orhun/rustypaste.git

if [[ ! -d "/opt/${APPLICATION}" ]]; then
    msg_error "Git clone has failed"
    exit
fi

cd ${APPLICATION}
git fetch --tags
git checkout ${RELEASE} # chekcing out to latest release

sed -i 's|^address = ".*"|address = "0.0.0.0:8000"|' config.toml # changing the ip and port

msg_info "Compiling ${APPLICATION}"
cargo build --locked --release # creating the binary

if [[ ! -f "/opt/${APPLICATION}/target/release/rustypaste" ]]; then
    msg_error "Cargo build failed"
    exit
fi

echo "${RELEASE}" >/opt/${APPLICATION}_version.txt # creating version file for the update function
msg_ok "Setting up ${APPLICATION} is Done!"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
WorkingDirectory=/opt/rustypaste
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
