#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: stout01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setup Python3"
$STD apt-get install -y \
  python3 \
  python3-dev \
  python3-pip
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
msg_ok "Setup Python3"

msg_info "Installing ${APPLICATION}"
$STD pip install 'litellm[proxy]'
$STD pip install 'prisma'
msg_ok "Installed ${APPLICATION}"

PG_VERSION="17" setup_postgresql

msg_info "Setting up PostgreSQL"
DB_NAME="litellm_db"
DB_USER="${APPLICATION}"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
# $STD sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" $DB_NAME
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
{
  echo "${APPLICATION} Credentials"
  echo "Database Name: $DB_NAME"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
} >>~/litellm.creds
msg_ok "Set up PostgreSQL"

msg_info "Creating Service"
mkdir -p /opt
cat <<EOF >/opt/"${APPLICATION}".yaml
general_settings:
  master_key: sk-1234
  database_url: postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME
  store_model_in_db: true
  use_prisma_migrate: true
EOF

cat <<EOF >/etc/systemd/system/"${APPLICATION}".service
[Unit]
Description=LiteLLM

[Service]
Type=simple
ExecStart=litellm --config /opt/"${APPLICATION}".yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now "${APPLICATION}"
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
