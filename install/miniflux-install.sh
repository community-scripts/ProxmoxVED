#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: omernaveedxyz
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://miniflux.app/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setting up PostgreSQL Database"
PG_VERSION=17 setup_postgresql
DB_NAME=miniflux
DB_USER=miniflux
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER;"
$STD sudo -u postgres psql -c "CREATE EXTENSION hstore;"
msg_ok "Set up PostgreSQL Database"

msg_info "Installing Miniflux"
$STD echo "deb https://repo.miniflux.app/apt/ * *" | sudo tee /etc/apt/sources.list.d/miniflux.list >/dev/null
$STD apt update
$STD apt install miniflux
msg_ok "Installed Miniflux"

msg_info "Configuring Miniflux"
{
  echo -n "user=$DB_USER password=$DB_PASS dbname=$DB_NAME sslmode=disable"
} >>/etc/miniflux-db.creds
chmod 600 /etc/miniflux-db.creds
chown miniflux:miniflux /etc/miniflux-db.creds

cat <<EOF >/etc/miniflux.conf
# See https://miniflux.app/docs/configuration.html
DATABASE_URL_FILE=/etc/miniflux-db.creds
CREATE_ADMIN=1
ADMIN_USERNAME=admin
ADMIN_PASSWORD=changeme
EOF

miniflux -migrate -config-file /etc/miniflux.conf
msg_ok "Configured Miniflux"

msg_info "Starting Service"
systemctl enable -q --now miniflux
msg_ok "Started Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned"
