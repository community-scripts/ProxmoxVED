#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.postgresql.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add \
    newt \
    curl \
    openssh \
    nano \
    mc \
    gpg

msg_ok "Installed Dependencies"

msg_info "Installing PostgreSQL and Dependencies"
apk add --no-cache postgresql postgresql-contrib
msg_ok "Installed PostgreSQL"

msg_info "Initializing PostgreSQL Database"
mkdir -p /var/lib/postgresql
chown postgres:postgres /var/lib/postgresql
sudo -u postgres initdb -D /var/lib/postgresql/data
msg_ok "Initialized PostgreSQL Database"

msg_info "Creating PostgreSQL Service"
service_path="/etc/init.d/postgresql"

echo '#!/sbin/openrc-run
description="PostgreSQL Database Server"

command="/usr/bin/postgres"
command_args="-D /var/lib/postgresql/data"
command_user="postgres"
pidfile="/var/run/postgresql.pid"

depend() {
    use net
}' >$service_path

chmod +x $service_path
rc-update add postgresql default
msg_ok "Created PostgreSQL Service"

msg_info "Starting PostgreSQL"
service postgresql start
msg_ok "Started PostgreSQL"

motd_ssh
customize
