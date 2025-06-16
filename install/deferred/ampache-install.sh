#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
apt-get install -y \
    apache2 \
    cron \
    flac \
    vorbis-tools \
    lame \
    ffmpeg \
    lsb-release \
    gosu \
    wget \
    curl \
    git \
    make \
    inotify-tools \
    libavcodec-extra \
    libev-libevent-dev \
    libmp3lame-dev \
    libtheora-dev \
    libvorbis-dev \
    libvpx-dev
msg_ok "Installed Dependencies"

PHP_VERSION=8.4
PHP_MODULE=bcmath,bz2,cli,common,curl,fpm,gd,imagick,intl,mbstring,mysql,sqlite3,xml,xmlrpc,zip
PHP_APACHE=YES
setup_php
setup_mariadb

msg_info "Setting up Database"
DB_NAME=ampache2
DB_USER=ampache2
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
sudo mysql -u root -e "CREATE DATABASE $DB_NAME;"
sudo mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password AS PASSWORD('$DB_PASS');"
sudo mysql -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
echo "" >>~/ampache.creds
echo -e "Ampache Database User: \e $DB_USER\e" >>~/ampache.creds
echo -e "Ampache Database Password: \e$DB_PASS\e" >>~/ampache.creds
echo -e "Ampache Database Name: \e$DB_NAME\e" >>~/ampache.creds
msg_ok "Set up database"

msg_info "Installing Ampache(Patience)"
cd /opt
AMPACHE_VERSION=$(wget -q https://github.com/ampache/ampache/releases/latest -O - | grep "title>Release" | cut -d " " -f 4)
wget https://github.com/ampache/ampache/releases/download/${AMPACHE_VERSION}/ampache-${AMPACHE_VERSION}_all_php8.4.zip
unzip -q ampache-${AMPACHE_VERSION}_all_php8.4.zip -d ampache
rm -rf /var/www/html
ln -s /opt/ampache/public /var/www/html
sudo mv /opt/ampache/rest/.htaccess.dist /opt/ampache/rest/.htaccess
sudo mv /opt/ampache/play/.htaccess.dist /opt/ampache/play/.htaccess
sudo mv /opt/ampache/channel/.htaccess.dist /opt/ampache/channel/.htaccess
sudo cp /opt/ampache/config/ampache.cfg.php.dist /opt/ampache/config/ampache.cfg.php
sudo chmod 664 /opt/ampache/rest/.htaccess /opt/ampache/play/.htaccess
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 50M/' /etc/php/8.4/apache2/php.ini &&
    sudo sed -i 's/post_max_size = .*/post_max_size = 50M/' /etc/php/8.4/apache2/php.ini &&
    sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.4/apache2/php.ini &&
    sudo sed -i 's/memory_limit = .*/memory_limit = 256M/' /etc/php/8.4/apache2/php.ini &&
    sudo systemctl restart apache2
msg_ok "Installed Ampache"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
