#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://akaunting.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  caddy \
  build-essential
msg_ok "Installed Dependencies"

PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULES="bcmath,gd,intl,xml,zip,pdo_mysql,mbstring,curl" setup_php
setup_composer
setup_mariadb
NODE_VERSION="22" setup_nodejs
MARIADB_DB_NAME="akaunting" MARIADB_DB_USER="akaunting" setup_mariadb_db

fetch_and_deploy_gh_release "akaunting" "akaunting/akaunting" "tarball"

msg_info "Setting up Akaunting"
cd /opt/akaunting
$STD composer install --no-dev --optimize-autoloader
$STD npm install
$STD npm run production
cat <<EOF >/opt/akaunting/.env
APP_NAME=Akaunting
APP_ENV=production
APP_DEBUG=false
APP_URL=http://${LOCAL_IP}

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${MARIADB_DB_NAME}
DB_USERNAME=${MARIADB_DB_USER}
DB_PASSWORD=${MARIADB_DB_PASS}

CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_CONNECTION=sync
EOF
$STD php artisan key:generate
mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
chown -R www-data:www-data /opt/akaunting
chmod -R 775 storage bootstrap/cache
$STD php artisan migrate --force --seed
msg_ok "Set up Akaunting"

msg_info "Configuring Caddy"
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
cat <<EOF >/etc/caddy/Caddyfile
:80 {
    root * /opt/akaunting/public
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
