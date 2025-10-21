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
$STD sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION hstore;"
$STD echo "localhost:5432:$DB_NAME:$DB_USER:$DB_PASSWORD" | sudo tee ~/.pgpass >/dev/null
$STD chmod 0600 ~/.pgpass
msg_ok "Set up PostgreSQL Database"

msg_info "Installing Miniflux"
fetch_and_deploy_gh_release "miniflux" "miniflux/v2" "tarball" "latest"
msg_ok "Installed Miniflux"

msg_info "Configuring Miniflux"
cat <<EOF >/etc/miniflux.conf
# See https://miniflux.app/docs/configuration.html
DATABASE_URL=user=$DB_USER password=$DB_PASS dbname=$DB_NAME sslmode=disable
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
$STD apt -y clean
msg_ok "Cleaned"
