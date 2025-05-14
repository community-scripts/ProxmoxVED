#!/usr/bin/env bash

# Copyright (c) 2021-2024 communtiy-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="16" install_postgresql
PHP_VERSION=8.3 PHP_MODULE="bcmath,bz2,cli,exif,common,curl,fpm,gd,imagick,intl,mbstring,pgsql,sqlite3,xml,xmlrpc,zip" install_php
NODE_VERSION=22 NODE_MODULE="yarn,npm@latest" install_node_and_modules
install_composer

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  nginx \
  apt-transport-https \
  lsb-release \
  ffmpeg \
  cron \
  libapache2-mod-xsendfile \
  libzip-dev \
  locales \
  libpng-dev \
  libjpeg62-turbo-dev \
  libpq-dev \
  libwebp-dev
msg_ok "Installed Dependencies"

# PG_VERSION="16" install_postgresql
# PHP_VERSION=8.3 PHP_MODULE="bcmath,bz2,cli,exif,common,curl,fpm,gd,imagick,intl,mbstring,pgsql,sqlite3,xml,xmlrpc,zip" install_php
# NODE_VERSION=22 NODE_MODULE="yarn,npm@latest" install_node_and_modules
# install_composer

msg_info "Setting up PostgreSQL Database"
DB_NAME=koel_db
DB_USER=koel
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
APP_SECRET=$(openssl rand -base64 32)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "Koel-Credentials"
  echo "Koel Database User: $DB_USER"
  echo "Koel Database Password: $DB_PASS"
  echo "Koel Database Name: $DB_NAME"
} >>~/koel.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Installing Koel(Patience)"
RELEASE=$(curl -fsSL https://github.com/koel/koel/releases/latest | grep "title>Release" | cut -d " " -f 4)
mkdir -p /opt/koel_{media,sync}
curl -fsSL https://github.com/koel/koel/releases/download/${RELEASE}/koel-${RELEASE}.zip -o /opt/koel.zip
unzip -q /opt/koel.zip
cd /opt/koel
mv .env.example .env
$STD composer install --no-interaction
sed -i -e "s/DB_CONNECTION=.*/DB_CONNECTION=pgsql/" \
  -e "s/DB_HOST=.*/DB_HOST=localhost/" \
  -e "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" \
  -e "s/DB_PORT=.*/DB_PORT=5432/" \
  -e "s|APP_KEY=.*|APP_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)|" \
  -e "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" \
  -e "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" \
  -e "s|MEDIA_PATH=.*|MEDIA_PATH=/opt/koel_media|" \
  -e "s|FFMPEG_PATH=/usr/local/bin/ffmpeg|FFMPEG_PATH=/usr/bin/ffmpeg|" /opt/koel/.env
php artisan koel:init --no-assets
chown -R :www-data /opt/*
chmod -R g+r /opt/*
chmod -R g+rw /opt/*
chown -R www-data:www-data /opt/*
chmod -R 755 /opt/*
msg_ok "Installed Koel"

msg_info "Set up web services"
cat <<EOF >/etc/nginx/sites-available/koel
server {
    listen          *:80;
    server_name     koel.local;
    root            /opt/koel/public;
    index           index.php;

    gzip            on;
    gzip_types      text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript application/json;
    gzip_comp_level 9;

    send_timeout    3600;
    client_max_body_size 200M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location /media/ {
        alias /opt/koel_media;
        autoindex on;
        access_log /var/log/nginx/koel.access.log;
        error_log  /var/log/nginx/koel.error.log;
    }

    location ~ \.php$ {
        try_files \$uri \$uri/ /index.php?\$args;

        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param PATH_TRANSLATED \$document_root\$fastcgi_path_info;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;

    }
}
EOF
ln -s /etc/nginx/sites-available/koel /etc/nginx/sites-enabled/koel
systemctl restart php8.3-fpm
systemctl reload nginx
msg_ok "Created Services"

msg_info "Adding Cronjob (Daily Midnight)"
cat <<EOF >/opt/koel_sync/koel_sync.cron
0 0 * * * cd /opt/koel/ && /usr/bin/php artisan koel:sync >/opt/koel_sync/koel_sync.log 2>&1
EOF
crontab /opt/koel_sync/koel_sync.cron

msg_ok "Cronjob successfully added"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/koel.zip
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
