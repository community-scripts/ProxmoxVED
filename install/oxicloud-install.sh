#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DioCrafts/OxiCloud

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="oxicloud" PG_DB_USER="oxicloud" setup_postgresql_db
fetch_and_deploy_gh_release "OxiCloud" "DioCrafts/OxiCloud" "tarball" "latest" "/opt/oxicloud"
TOOLCHAIN="$(sed -n '2s/[^:]*://p' /opt/oxicloud/Dockerfile | awk -F- '{print $1}')"
RUST_TOOLCHAIN=$TOOLCHAIN setup_rust

msg_info "Building OxiCloud"
cd /opt/oxicloud
export DATABASE_URL="postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost/${PG_DB_NAME}"
$STD cargo build --release
mv target/release/oxicloud /usr/bin/oxicloud && chmod +x /usr/bin/oxicloud
msg_ok "Built OxiCloud"

msg_info "Configuring OxiCloud"
mkdir -p {/mnt/oxicloud,/etc/oxicloud}
sed -e 's|_STORAGE_PATH=.*|_STORAGE_PATH=/mnt/oxicloud|' \
  -e 's|_SERVER_HOST=.*|_SERVER_HOST=0.0.0.0|' \
  -e "s|^#OXICLOUD_BASE_URL=.*|OXICLOUD_BASE_URL=${LOCAL_IP}:8086|" \
  -e "s|_STRING=.*|_STRING=${DATABASE_URL}|" \
  -e "s|DATABASE_URL=.*|DATABASE_URL=${DATABASE_URL}|" \
  -e "s|^#OXICLOUD_JWT_SECRET=.*|OXICLOUD_JWT_SECRET=$(openssl rand -hex 32)|" \
  -e 's|^#OXICLOUD_ENABLE|OXICLOUD_ENABLE|g' \
  /opt/oxicloud/example.env >/etc/oxicloud/.env
chmod 600 /etc/oxicloud/.env
msg_ok "Configured OxiCloud"

msg_info "Creating OxiCloud Service"
cat <<EOF >/etc/systemd/system/oxicloud.service
[Unit]
Description=OxiCloud Service
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/oxicloud/.env
ExecStart=/usr/bin/oxicloud
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable -q --now oxicloud
msg_ok "Created OxiCloud Service"

motd_ssh
customize
cleanup_lxc
