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
    sudo \
    nano \
    mc \
    gpg

msg_ok "Installed Dependencies"

msg_info "Installing PostgreSQL and Dependencies"
$STD apk add --no-cache postgresql postgresql-contrib
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

msg_info "Configuring PostgreSQL"
cat <<EOF >/var/lib/postgresql/data/pg_hba.conf
# PostgreSQL Client Authentication Configuration File
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             0.0.0.0/24              md5
host    all             all             ::1/128                 scram-sha-256
host    all             all             0.0.0.0/0               md5
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256
EOF

cat <<EOF >/var/lib/postgresql/data/postgresql.conf
data_directory = '/var/lib/postgresql/data'
hba_file = '/var/lib/postgresql/data/pg_hba.conf'
ident_file = '/var/lib/postgresql/data/pg_ident.conf'
external_pid_file = '/var/run/postgresql.pid'
listen_addresses = '*'
port = 5432
max_connections = 100
unix_socket_directories = '/var/run/postgresql'
ssl = off
shared_buffers = 128MB
dynamic_shared_memory_type = posix
max_wal_size = 1GB
min_wal_size = 80MB
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = 'Etc/UTC'
cluster_name = 'alpine_pg'
datestyle = 'iso, mdy'
timezone = 'Etc/UTC'
lc_messages = 'C'
lc_monetary = 'C'
lc_numeric = 'C'
lc_time = 'C'
default_text_search_config = 'pg_catalog.english'
include_dir = 'conf.d'
EOF
msg_ok "Configured PostgreSQL"

msg_info "Starting PostgreSQL"
service postgresql start
msg_ok "Started PostgreSQL"

read -p "Do you want to install Adminer with Lighttpd? (y/N): " install_adminer
if [[ "$install_adminer" =~ ^[Yy]$ ]]; then
    msg_info "Installing Adminer with Lighttpd"
    msg_ok "Installed Lighttpd and PHP"

    msg_info "Downloading Adminer"
    mkdir -p /var/www/adminer
    curl -fsSL "https://www.adminer.org/latest.php" -o /var/www/adminer/index.php
    chown -R lighttpd:lighttpd /var/www/adminer
    msg_ok "Installed Adminer"

    msg_info "Configuring Lighttpd"
    echo 'server.modules = (
    "mod_access",
    "mod_alias",
    "mod_fastcgi"
)

server.document-root = "/var/www/adminer"
server.port = 8080
server.bind = "0.0.0.0"
index-file.names = ("index.php")

fastcgi.server = ( ".php" => ((
  "bin-path" => "/usr/bin/php-cgi",
  "socket" => "/var/run/php-fcgi.sock"
)))

server.dir-listing = "disable"

accesslog.filename = "/var/log/lighttpd/access.log"
server.errorlog = "/var/log/lighttpd/error.log"

include "modules.conf"' >/etc/lighttpd/lighttpd.conf

    rc-update add lighttpd default
    msg_ok "Configured Lighttpd"

    msg_info "Starting Lighttpd"
    service lighttpd start
    msg_ok "Started Lighttpd (Adminer available on Port 8080)"
else
    msg_ok "Skipped Adminer and Lighttpd installation."
fi

motd_ssh
customize
