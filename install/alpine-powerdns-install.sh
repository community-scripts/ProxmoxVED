#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.powerdns.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing PowerDNS"
$STD apk add --no-cache pdns pdns-backend-sqlite3 pdns-doc
msg_ok "Installed PowerDNS"

msg_info "Configuring PowerDNS"
sed -i '/^# launch=$/c\launch=gsqlite3\ngsqlite3-database=/var/lib/powerdns/pdns.sqlite3' /etc/pdns/pdns.conf
mkdir /var/lib/powerdns
sqlite3 /var/lib/powerdns/pdns.sqlite3 < /usr/share/doc/pdns/schema.sqlite3.sql
chown -R pdns:pdns /var/lib/powerdns
msg_ok "Configured PowerDNS"

msg_info "Creating Service"
$STD rc-update add pdns default
$STD rc-service pdns start
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
