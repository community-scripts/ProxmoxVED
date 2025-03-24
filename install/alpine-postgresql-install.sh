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

read -p "Do you want to install Adminer with Lighttpd? (y/N): " install_adminer
 if [[ "$install_adminer" =~ ^[Yy]$ ]]; then
    msg_info "Installing Adminer with Lighttpd"
  apk add --no-cache lighttpd php php-pdo_pgsql php-session php-json php-mbstring
  msg_ok "Installed Lighttpd and PHP"

  msg_info "Downloading Adminer"
  mkdir -p /var/www/adminer
  curl -L "https://www.adminer.org/latest.php" -o /var/www/adminer/index.php
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

include "modules.conf"' > /etc/lighttpd/lighttpd.conf

  rc-update add lighttpd default
  msg_ok "Configured Lighttpd"

  msg_info "Starting Lighttpd"
  service lighttpd start
  msg_ok "Started Lighttpd (Adminer available on Port 8080)"
  else
    msg_ok "Skipped Adminer and Lighttpd installation."
  fi
}

motd_ssh
customize
