#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: PouletteMC
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://surrealdb.com

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
  sudo \
  mc
msg_ok "Installed Dependencies"

msg_info "Installing SurrealDB"
$STD bash <(curl -sSf https://install.surrealdb.com)
msg_ok "Installed SurrealDB"

msg_info "Configuring SurrealDB"
mkdir -p /opt/surrealdb/data
SURREALDB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
cat <<EOF >/opt/surrealdb/.env
SURREALDB_PASS=${SURREALDB_PASS}
EOF
{
  echo "SurrealDB Credentials"
  echo "Username: root"
  echo "Password: ${SURREALDB_PASS}"
} >>~/surrealdb.creds
msg_ok "Configured SurrealDB"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/surrealdb.service
[Unit]
Description=SurrealDB Server
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/surrealdb/.env
ExecStart=/usr/local/bin/surreal start --bind 0.0.0.0:8000 --user root --pass \${SURREALDB_PASS} rocksdb:///opt/surrealdb/data/srdb.db
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now surrealdb
msg_ok "Created Service"

RELEASE=$(curl -fsSL https://api.github.com/repos/surrealdb/surrealdb/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
echo "${RELEASE}" >/opt/SurrealDB_version.txt

motd_ssh
customize
cleanup_lxc
