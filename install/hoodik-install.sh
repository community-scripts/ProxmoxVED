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

#msg_info "Installing Dependencies"
#$STD apt-get install -y \
#  pkg-config \
#  libssl-dev \
#  libc6-dev \
#  libpq-dev \
#  clang \
#  llvm \
#  nettle-dev \
#  build-essential \
#  make
#msg_ok "Installed Dependencies"

#setup_rust
#NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
#fetch_and_deploy_gh_release "hoodik" "hudikhq/hoodik" "tarball" "latest" "/opt/hoodik"
fetch_and_deploy_gh_release "hoodik" "hudikhq/hoodik" "prebuild" "latest" "/opt/hoodik" "*x86_64.tar.gz"

#msg_info "Installing wasm-pack"
#$STD cargo install wasm-pack
#msg_ok "Installed wasm-pack"

#msg_info "Building Hoodik Frontend"
#cd /opt/hoodik
#$STD yarn install --frozen-lockfile
#$STD yarn wasm-pack
#$STD yarn web:build
#msg_ok "Built Hoodik Frontend"

#msg_info "Building Hoodik Backend"
#cd /opt/hoodik
#$STD cargo build --release
#cp /opt/hoodik/target/release/hoodik /usr/local/bin/hoodik
#chmod +x /usr/local/bin/hoodik
#msg_ok "Built Hoodik Backend"

#msg_info "Cleaning up build artifacts"
#rm -rf /opt/hoodik/target
#rm -rf /root/.cargo/registry
#rm -rf /opt/hoodik/node_modules
#msg_ok "Cleaned up build artifacts"

msg_info "Configuring Hoodik"
mkdir -p /opt/hoodik_data
JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
cat <<EOF >/opt/hoodik/.env
DATA_DIR=/opt/hoodik_data
HTTP_PORT=5443
HTTP_ADDRESS=0.0.0.0
JWT_SECRET=${JWT_SECRET}
APP_URL=http://127.0.0.1:5443
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
WorkingDirectory=/opt/hoodik_data
EnvironmentFile=/opt/hoodik/.env
#ExecStart=/usr/local/bin/hoodik
ExecStart=/opt/hoodik
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
