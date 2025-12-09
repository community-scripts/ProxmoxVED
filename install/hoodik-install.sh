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
$STD apt-get install -y \
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

setup_rust
fetch_and_deploy_gh_release "hoodik" "hudikhq/hoodik" "tarball" "latest" "/opt/hoodik"

msg_info "Building Hoodik"
cd /opt/hoodik
source ~/.cargo/env
$STD cargo build --release
cp /opt/hoodik/target/release/hoodik /usr/local/bin/hoodik
chmod +x /usr/local/bin/hoodik
rm -rf /opt/hoodik/target
msg_ok "Built Hoodik"

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
cleanup_lxc
