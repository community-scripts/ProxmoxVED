#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/hudikhq/hoodik

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  pkg-config \
  libssl-dev \
  libc6-dev \
  libpq-dev \
  clang \
  llvm \
  nettle-dev \
  build-essential \
  make
msg_ok "Installed Dependencies"

msg_info "Installing Rust"
$STD bash <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs) -y
source ~/.cargo/env
msg_ok "Installed Rust"

msg_info "Building Hoodik (Patience - this takes 10-15 minutes)"
RELEASE=$(curl -fsSL https://api.github.com/repos/hudikhq/hoodik/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
cd /opt
curl -fsSL "https://github.com/hudikhq/hoodik/archive/refs/tags/${RELEASE}.zip" -o "${RELEASE}.zip"
unzip -q "${RELEASE}.zip"
mv "hoodik-${RELEASE#v}" hoodik
cd /opt/hoodik
$STD cargo build --release
cp /opt/hoodik/target/release/hoodik /usr/local/bin/hoodik
chmod +x /usr/local/bin/hoodik
echo "${RELEASE}" >/opt/hoodik_version.txt
msg_ok "Built Hoodik ${RELEASE}"

msg_info "Configuring Hoodik"
mkdir -p /opt/hoodik_data
JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
cat <<EOF >/opt/hoodik/.env
DATA_DIR=/opt/hoodik_data
HTTP_PORT=5443
HTTP_ADDRESS=0.0.0.0
JWT_SECRET=${JWT_SECRET}
APP_URL=https://localhost:5443
SSL_DISABLED=true
MAILER_TYPE=none
RUST_LOG=hoodik=info,error=info
EOF
msg_ok "Configured Hoodik"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/hoodik.service
[Unit]
Description=Hoodik - Encrypted File Storage
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/hoodik
EnvironmentFile=/opt/hoodik/.env
ExecStart=/usr/local/bin/hoodik -a 0.0.0.0 -p 5443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hoodik.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f /opt/${RELEASE}.zip
rm -rf /opt/hoodik/target
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
