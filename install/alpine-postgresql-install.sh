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

msg_info "Installing PostgreSQL"
$STD apk add --no-cache postgresql16 postgresql16-contrib postgresql16-openrc
msg_ok "Installed PostgreSQL"

msg_info "Enabling PostgreSQL Service"
rc-update add postgresql default
msg_ok "Enabled PostgreSQL Service"

msg_info "Starting PostgreSQL"
rc-service postgresql start
msg_ok "Started PostgreSQL"

msg_info "Configuring PostgreSQL for External Access"
conf_file="/etc/postgresql16/postgresql.conf"
hba_file="/etc/postgresql16/pg_hba.conf"

sed -i 's/^#listen_addresses =.*/listen_addresses = '\''*'\''/' "$conf_file"

sed -i '/^host\s\+all\s\+all\s\+127.0.0.1\/32\s\+md5/ s/.*/host all all 0.0.0.0\/0 md5/' "$hba_file"

rc-service postgresql restart
msg_ok "Configured and Restarted PostgreSQL"

read -p "Do you want to install Adminer with Lighttpd? (y/N): " install_adminer
if [[ "$install_adminer" =~ ^[Yy]$ ]]; then
    msg_info "Installing Adminer with Lighttpd"
    apk add --no-cache php php-pdo_pgsql php-session php-json php-mbstring lighttpd
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
server.port = 9000
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
