#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/bluecherrydvr/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y python3-distutils
msg_ok "Installed Dependencies"

install_mariadb

msg_info "Setting up Bluecherry"
export DEBIAN_FRONTEND=noninteractive
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
MYSQL_ROOT_PASS="$(openssl rand -base64 18 | cut -c1-13)"
curl -fsSL https://dl.bluecherrydvr.com/key/bluecherry.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/bluecherry.gpg
echo "deb http://dl.bluecherrydvr.com bookworm main" >/etc/apt/sources.list.d/bluecherry.list
$STD apt-get update
echo "bluecherry bluecherry/db_host string localhost" | debconf-set-selections
echo "bluecherry bluecherry/db_name string bluecherry" | debconf-set-selections
echo "bluecherry bluecherry/db_password password $DB_PASS" | debconf-set-selections
echo "bluecherry bluecherry/db_user string bluecherry" | debconf-set-selections
echo "bluecherry bluecherry/mysql_admin_login string root" | debconf-set-selections
echo "bluecherry bluecherry/mysql_admin_password password $MYSQL_ROOT_PASS" | debconf-set-selections
$STD apt-get install bluecherry
msg_ok "Done setting up bluecherry"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bluecherry.service
[Unit]
Description=bluecherry Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bluecherry
ExecStart=/opt/bluecherry/bluecherry
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bluecherry
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

motd_ssh
customize
