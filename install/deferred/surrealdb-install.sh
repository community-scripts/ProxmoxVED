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

fetch_and_deploy_gh_release "surrealdb" "surrealdb/surrealdb" "prebuild" "latest" "/opt/surrealdb" "surreal-v*.linux-amd64.tgz"
chmod +x /opt/surrealdb/surreal
ln -sf /opt/surrealdb/surreal /usr/local/bin/surreal

msg_info "Configuring SurrealDB"
mkdir -p /opt/surrealdb/data
SURREALDB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
cat <<EOF >/opt/surrealdb/.env
SURREALDB_PASS=${SURREALDB_PASS}
EOF
msg_ok "Configured SurrealDB"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/surrealdb.service
[Unit]
Description=SurrealDB Server
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/surrealdb/.env
ExecStart=/opt/surrealdb/surreal start --bind 0.0.0.0:8000 --user root --pass \${SURREALDB_PASS} rocksdb:///opt/surrealdb/data/srdb.db
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now surrealdb
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
