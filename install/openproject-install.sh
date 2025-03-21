#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: michelroegl-brunner
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
install_core_deps

msg_info "Installing Dependencies"
$STD apt-get install -y \
    sudo \
    mc \
    curl \
    apt-transport-https \
    ca-certificates \
    gpg
msg_ok "Installed Dependencies"

msg_info "Adding Repository"
wget -qO- https://dl.packager.io/srv/opf/openproject/key | gpg --dearmor >/etc/apt/trusted.gpg.d/packager-io.gpg
wget -O /etc/apt/sources.list.d/openproject.list https://dl.packager.io/srv/opf/openproject/stable/15/installer/debian/12.repo
msg_ok "Added Repository"

msg_info "Setting up PostgreSQL Repository"
VERSION="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"
echo "deb http://apt.postgresql.org/pub/repos/apt ${VERSION}-pgdg main" >/etc/apt/sources.list.d/pgdg.list
curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --output /etc/apt/trusted.gpg.d/postgresql.gpg
msg_ok "Setup PostgreSQL Repository"

msg_info "Installing PostgreSQL"
$STD apt-get update
$STD apt-get install -y postgresql
msg_ok "Installed PostgreSQL"

msg_info "Setting up PostgreSQL"
DB_NAME=openproject
DB_USER=openproject
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE template0;"
{
    echo "Netbox-Credentials"
    echo -e "Netbox Database User: \e[32m$DB_USER\e[0m"
    echo -e "Netbox Database Password: \e[32m$DB_PASS\e[0m"
    echo -e "Netbox Database Name: \e[32m$DB_NAME\e[0m"
} >>~/openproject.creds
msg_ok "Set up PostgreSQL"

msg_info "Installing OpenProject"
$STD apt-get update
$STD apt-get install -y openproject
msg_ok "Installed OpenProject"

msg_info "Setting up OpenProject"
$STD sudo openproject configure
$STD openproject config:set DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
msg_ok "Set up OpenProject"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
