#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: phof
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (PostgreSQL, curl, logrotate, openssl)"
$STD apk add --no-cache postgresql postgresql-contrib curl logrotate openssl
msg_ok "Installed Dependencies"

msg_info "Initializing PostgreSQL Database"
if [ ! -d /var/lib/postgresql ]; then
  $STD mkdir -p /var/lib/postgresql
fi
$STD su - postgres -c 'initdb -D /var/lib/postgresql/data'
msg_ok "Initialized PostgreSQL"

msg_info "Creating Miniflux Database and User"
DB_USER="miniflux"
DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)
DB_NAME="miniflux"

rc-service postgresql start || service postgresql start
sleep 2
$STD su - postgres -c "createuser ${DB_USER}"
$STD su - postgres -c "createdb -O ${DB_USER} ${DB_NAME}"
$STD su - postgres -c "psql -c \"ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}'\""
$STD su - postgres -c "psql -d ${DB_NAME} -c 'CREATE EXTENSION IF NOT EXISTS hstore'"
{
  echo "Miniflux Database Credentials"
  echo "DB User: ${DB_USER}"
  echo "DB Password: ${DB_PASS}"
  echo "DB Name: ${DB_NAME}"
} >~/miniflux-db.creds
msg_ok "Created Database and User"

msg_info "Installing Miniflux (apk packages)"
# Ensure community repo is enabled (edge community as per docs, if needed)
if ! grep -q "/edge/community" /etc/apk/repositories; then
  echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >>/etc/apk/repositories
  $STD apk update
fi
$STD apk add --no-cache miniflux miniflux-openrc miniflux-doc || true
msg_ok "Installed Miniflux"

msg_info "Configuring Miniflux"
mkdir -p /etc/miniflux
IPADDRESS=$(hostname -i)
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)
{
  echo "LOG_DATE_TIME=yes"
  echo "LISTEN_ADDR=0.0.0.0:8080"
  echo "DATABASE_URL=user=${DB_USER} password=${DB_PASS} dbname=${DB_NAME} sslmode=disable"
  echo "RUN_MIGRATIONS=1"
  echo "CREATE_ADMIN=1"
  echo "ADMIN_USERNAME=${ADMIN_USER}"
  echo "ADMIN_PASSWORD=${ADMIN_PASS}"
} >/etc/miniflux.conf
{
  echo "Miniflux Admin Credentials"
  echo "Username: ${ADMIN_USER}"
  echo "Password: ${ADMIN_PASS}"
  echo "URL: http://${IPADDRESS}:8080"
} >~/miniflux-admin.creds
msg_ok "Configured Miniflux"

msg_info "Applying Database Migrations and Creating Admin"
miniflux -c /etc/miniflux.conf -migrate
msg_ok "Applied Migrations and Created Admin"

msg_info "Enabling and Starting Miniflux"
$STD rc-update add miniflux default
$STD rc-service miniflux start
msg_ok "Miniflux Started"

motd_ssh
customize

msg_info "Cleaning up"
$STD apk cache clean || true
msg_ok "Cleaned"


