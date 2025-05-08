#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: j4v3l (https://github.com/j4v3l)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y \
  lsb-release \
  openssl \
  ca-certificates
msg_ok "Installed Dependencies"

PG_VERSION=14 install_postgresql

msg_info "Configuring PostgreSQL for Atuin"
PG_USER="atuin"
PG_PASSWORD=$(openssl rand -base64 24)
PG_DB="atuin"
$STD apt-get install -y postgresql-contrib-$PG_VERSION

$STD su postgres <<EOF
createuser $PG_USER
createdb -O $PG_USER $PG_DB
psql -c "ALTER USER $PG_USER WITH PASSWORD '$PG_PASSWORD';"
EOF

{
  echo "Atuin Database Credentials"
  echo "Database User: $PG_USER"
  echo "Database Password: $PG_PASSWORD"
  echo "Database Name: $PG_DB"
} >>/root/${APPLICATION}.creds

msg_ok "Configured PostgreSQL for Atuin"

msg_info "Installing Atuin"
$STD curl -fsSL https://get.atuin.sh | bash
msg_ok "Installed Atuin"

msg_info "Configuring Atuin Server"
mkdir -p /root/.config/atuin/
cat >/root/.config/atuin/server.toml <<EOF
host = "0.0.0.0"
port = 8888
open_registration = true
db_uri = "postgres://$PG_USER:$PG_PASSWORD@localhost/$PG_DB"

# [tls]
# enable = true
# cert_path = "/path/to/cert.pem"
# pkey_path = "/path/to/key.pem"
EOF
msg_ok "Configured Atuin Server"

msg_info "Creating Atuin Service"
cat >/etc/systemd/system/atuin.service <<EOF
[Unit]
Description=Atuin Server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/atuin server start
Restart=on-failure
RestartSec=5s
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reload
$STD systemctl enable atuin
$STD systemctl start atuin
msg_ok "Created Atuin Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
