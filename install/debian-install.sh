#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# msg_info "Installing Dependencies"
# $STD apt-get install -y gnupg2
# msg_ok "Installed Dependencies"

# Example Setting for Test
#NODE_MODULE="pnpm@10.1,yarn"
#RELEASE=$(curl_handler -fsSL https://api.github.com/repos/babybuddy/babybuddy/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
#msg_ok "Get Release $RELEASE"
#NODE_VERSION="22" NODE_MODULE="yarn" install_node_and_modules

#PG_VERSION="15"
#MARIADB_VERSION="10.11"
#MYSQL_VERSION="8.0"

#install_postgresql
#install_mariadb
#install_mysql

# msg_info "Setup DISTRO env"
# DISTRO="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"
# msg_ok "Setup DISTRO"

# echo -e $DISTRO

# msg_info "Setting up PostgreSQL Repository"
# curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
# echo "deb https://apt.postgresql.org/pub/repos/apt ${DISTRO}-pgdg main" >/etc/apt/sources.list.d/pgdg.list
# apt-get update
# $STD apt-get install -y postgresql
# msg_ok "Set up PostgreSQL Repository"

# msg_info "Setting up Matrix Server"
# curl -fsSL https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg -o /usr/share/keyrings/matrix-org-archive-keyring.gpg
# echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian ${DISTRO} main" >/etc/apt/sources.list.d/matrix-org.list
# apt-get update
# $STD apt-get install -y matrix-synapse-py3
# msg_info "Set up Matrix Server"

# msg_info "Setup EVCC"
# curl -fsSL https://dl.evcc.io/public/evcc/stable/gpg.EAD5D0E07B0EC0FD.key | gpg --dearmor -o /etc/apt/keyrings/evcc-stable.gpg
# echo "deb [signed-by=/etc/apt/keyrings/evcc-stable.gpg] https://dl.evcc.io/public/evcc/stable/deb/debian ${DISTRO} main" >/etc/apt/sources.list.d/evcc-stable.list
# apt-get update
# $STD apt-get install -y evcc
# msg_ok "Setup EVCC"

# msg_info "Setup PHP"
# curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/deb.sury.org-php.gpg
# echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${DISTRO} main" >/etc/apt/sources.list.d/php.list
# apt-get update
# $STD apt-get install -y php
# msg_ok "Setup PHP"

# msg_info "Adding Adoptium repository"
# curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg
# echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${DISTRO} main" > /etc/apt/sources.list.d/adoptium.list
# apt-get update
# $STD apt-get install -y temurin-11-jdk
# msg_ok "Adoptium installed"

# msg_info "Adding Nginx repository"
# curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
# echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian ${DISTRO} nginx" > /etc/apt/sources.list.d/nginx.list
# apt-get update
# $STD apt-get install -y nginx=1.26.3*
# msg_ok "Nginx installed"

# msg_info "Adding MongoDB repository"
# curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
# echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] http://repo.mongodb.org/apt/debian ${DISTRO}/mongodb-org/7.0 main" > /etc/apt/sources.list.d/mongodb-org-7.0.list
# apt-get update
# $STD apt-get install -y mongodb-org
# msg_ok "MongoDB installed"

# msg_info "Adding SFTPGo repository"
# curl -fsSL https://ftp.osuosl.org/pub/sftpgo/apt/gpg.key | gpg --dearmor -o /usr/share/keyrings/sftpgo-archive-keyring.gpg
# echo "deb [signed-by=/usr/share/keyrings/sftpgo-archive-keyring.gpg] https://ftp.osuosl.org/pub/sftpgo/apt ${DISTRO} main" > /etc/apt/sources.list.d/sftpgo.list
# apt-get update
# $STD apt-get install -y sftpgo
# msg_ok "SFTPGo installed"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
