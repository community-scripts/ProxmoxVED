#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ampache/ampache

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  flac \
  vorbis-tools \
  lame \
  ffmpeg \
  inotify-tools \
  libavcodec-extra \
  libmp3lame-dev \
  libtheora-dev \
  libvorbis-dev \
  libvpx-dev
msg_ok "Installed Dependencies"

PHP_VERSION=8.4 PHP_MODULE=bcmath,bz2,curl,gd,imagick,intl,mbstring,mysql,sqlite3,xml,xmlrpc,zip PHP_APACHE=YES setup_php
setup_mariadb
MARIADB_DB_USER=ampache MARIADB_DB_NAME=ampache setup_mariadb_db

fetch_and_deploy_gh_release "ampache" "ampache/ampache" "prebuild" "latest" "/opt/ampache" "ampache-*_all_php8.4.zip"

msg_info "Setup Ampache"
rm -rf /var/www/html
ln -s /opt/ampache/public /var/www/html
mv /opt/ampache/rest/.htaccess.dist /opt/ampache/rest/.htaccess
mv /opt/ampache/play/.htaccess.dist /opt/ampache/play/.htaccess
mv /opt/ampache/channel/.htaccess.dist /opt/ampache/channel/.htaccess
cp /opt/ampache/config/ampache.cfg.php.dist /opt/ampache/config/ampache.cfg.php
chmod 664 /opt/ampache/rest/.htaccess /opt/ampache/play/.htaccess /opt/ampache/channel/.htaccess
chown -R www-data:www-data /opt/ampache
msg_ok "Set up Ampache"

msg_info "Configuring PHP"
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.4/apache2/php.ini
sed -i 's/post_max_size = .*/post_max_size = 100M/' /etc/php/8.4/apache2/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 600/' /etc/php/8.4/apache2/php.ini
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.4/apache2/php.ini
$STD a2enmod rewrite
$STD systemctl restart apache2
msg_ok "Configured PHP"

motd_ssh
customize
cleanup_lxc
