#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: community-scripts
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

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
  curl \
  gnupg2 \
  lsb-release \
  openssl \
  ca-certificates

# Add PostgreSQL repository
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" >/etc/apt/sources.list.d/pgdg.list
$STD apt-get update

# Install PostgreSQL 14 (required by Atuin)
$STD apt-get install -y postgresql-14 postgresql-contrib-14
msg_ok "Installed Dependencies"

msg_info "Configuring PostgreSQL for Atuin"
# Create user and database
PG_USER="atuin"
PG_PASSWORD=$(openssl rand -base64 24)
PG_DB="atuin"

# Create PostgreSQL user and database
$STD su postgres <<EOF
createuser $PG_USER
createdb -O $PG_USER $PG_DB
psql -c "ALTER USER $PG_USER WITH PASSWORD '$PG_PASSWORD';"
EOF

# Save credentials to a file
mkdir -p /root/.config/
echo "Atuin Database Credentials" >/root/atuin.creds
echo "----------------------------" >>/root/atuin.creds
echo "Database Host: localhost" >>/root/atuin.creds
echo "Database User: $PG_USER" >>/root/atuin.creds
echo "Database Password: $PG_PASSWORD" >>/root/atuin.creds
echo "Database Name: $PG_DB" >>/root/atuin.creds
echo "----------------------------" >>/root/atuin.creds
msg_ok "Configured PostgreSQL for Atuin"

msg_info "Installing Atuin"
# Install Atuin from official source
$STD curl -fsSL https://get.atuin.sh | bash
msg_ok "Installed Atuin"

msg_info "Configuring Atuin Server"
# Create server config directory
mkdir -p /root/.config/atuin/
cat >/root/.config/atuin/server.toml <<EOF
host = "0.0.0.0"
port = 8888
open_registration = true
db_uri = "postgres://$PG_USER:$PG_PASSWORD@localhost/$PG_DB"

# Uncomment and modify for TLS support
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

# Display information for connecting clients
IP=$(hostname -I | awk '{print $1}')
echo -e "\n📝 ${APP} Setup Information"
echo -e "-----------------------------------"
echo -e "Server URL: http://${IP}:8888"
echo -e "Credential file: /root/atuin.creds"
echo -e ""
echo -e "To connect clients:"
echo -e "1. Add to shell config (~/.bashrc, ~/.zshrc):"
echo -e "   export ATUIN_HOST=\"http://${IP}:8888\""
echo -e "2. Run on client:"
echo -e "   atuin register <username>"
echo -e "   atuin sync"
echo -e "-----------------------------------"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
