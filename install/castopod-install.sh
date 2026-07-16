#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://castopod.org/

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

PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULES="curl,exif,gd,intl,mbstring,mysql,xml,zip" setup_php
setup_ffmpeg
setup_mariadb
MARIADB_DB_NAME="castopod" MARIADB_DB_USER="castopod" setup_mariadb_db

GITLAB_URL="https://code.castopod.org" fetch_and_deploy_gl_release \
  "castopod" \
  "adaures/castopod" \
  "prebuild" \
  "latest" \
  "/opt/castopod" \
  "castopod-*.tar.gz"

cd /
msg_info "Configuring Castopod"
mkdir -p /opt/castopod/public/media /opt/castopod/writable
CASTOPOD_SALT=$(openssl rand -hex 32)
cat <<EOF >/opt/castopod/.env
app.baseURL="http://${LOCAL_IP}/"
media.baseURL="http://${LOCAL_IP}/media/"
admin.gateway="cp-admin"
auth.gateway="cp-auth"
analytics.salt="${CASTOPOD_SALT}"

database.default.hostname="127.0.0.1"
database.default.database="${MARIADB_DB_NAME}"
database.default.username="${MARIADB_DB_USER}"
database.default.password="${MARIADB_DB_PASS}"
database.default.DBPrefix="cp_"

cache.handler="file"
EOF
chown -R www-data:www-data /opt/castopod/public/media /opt/castopod/writable
chmod 640 /opt/castopod/.env
msg_ok "Configured Castopod"

msg_info "Configuring Caddy"
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
cat <<EOF >/etc/caddy/Caddyfile
:80 {
    root * /opt/castopod/public
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
usermod -aG www-data caddy
msg_ok "Configured Caddy"

msg_info "Creating Scheduled Tasks"
cat <<EOF >/etc/cron.d/castopod
* * * * * www-data /usr/bin/php /opt/castopod/spark tasks:run >/dev/null 2>&1
EOF
msg_ok "Created Scheduled Tasks"

systemctl enable -q --now php${PHP_VER}-fpm caddy

motd_ssh
customize
cleanup_lxc
