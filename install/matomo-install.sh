#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://matomo.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y caddy
msg_ok "Installed Dependencies"

PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="pdo_mysql,gd,mbstring,xml,curl,intl,zip,ldap" setup_php
setup_mariadb
MARIADB_DB_NAME="matomo" MARIADB_DB_USER="matomo" setup_mariadb_db

fetch_and_deploy_gh_release "matomo" "matomo-org/matomo" "prebuild" "latest" "/opt/matomo" "matomo-*.zip"

msg_info "Setting up Matomo"
mkdir -p /opt/matomo/tmp
chown -R www-data:www-data /opt/matomo
chmod -R 755 /opt/matomo/tmp
msg_ok "Set up Matomo"

msg_info "Configuring Caddy"
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
cat <<EOF >/etc/caddy/Caddyfile
:80 {
    root * /opt/matomo
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
usermod -aG www-data caddy
msg_ok "Configured Caddy"

systemctl enable -q --now php${PHP_VER}-fpm
systemctl restart caddy

motd_ssh
customize
cleanup_lxc
