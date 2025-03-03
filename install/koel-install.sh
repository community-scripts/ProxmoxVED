#!/usr/bin/env bash

# Copyright (c) 2021-2024 communtiy-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  postgresql \
  nginx \
  apt-transport-https \
  gnupg2 \
  lsb-release \
  ffmpeg \
  curl \
  unzip \
  sudo \
  mc \
  cron \
  libapache2-mod-xsendfile \
  libzip-dev \
  locales \
  libpng-dev \
  libjpeg62-turbo-dev \
  libpq-dev \
  libwebp-dev \
  libapache2-mod-php \
  composer
 msg_ok "Installed Dependencies"

msg_info "Setting up PSql Database"
DB_NAME=koel_db
DB_USER=koel
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
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
} >> ~/koel.creds
msg_ok "Set up PostgreSQL database"

msg_info "Setting up Node.js/Yarn"
mkdir -p /etc/apt/keyrings
$STD curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
$STD echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
$STD npm install -g npm@latest
$STD npm install -g yarn
msg_ok "Installed Node.js/Yarn"

msg_info "Setting up PHP"
$STD curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
$STD sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
$STD apt update
$STD apt install -y php8.3 php8.3-{bcmath,exif,bz2,cli,common,curl,fpm,gd,intl,sqlite3,mbstring,xml,zip,pgsql}
msg_ok "PHP successfully setup" 

msg_info "Installing Koel(Patience)"
RELEASE=$(wget -q https://github.com/koel/koel/releases/latest -O - | grep "title>Release" | cut -d " " -f 4)
cd /opt
mkdir -p /opt/koel_{media,sync}
wget -q https://github.com/koel/koel/releases/download/${RELEASE}/koel-${RELEASE}.zip
unzip -q koel-${RELEASE}.zip
chown -R :www-data /opt/*
chmod -R g+r /opt/*
chmod -R g+rw /opt/*
chown -R www-data:www-data /opt/*
chmod -R 755 /opt/*
cd /opt/koel
echo "export COMPOSER_ALLOW_SUPERUSER=1" >> ~/.bashrc
source ~/.bashrc
$STD composer update --no-interaction
$STD composer install --no-interaction
sudo sed -i -e "s/DB_CONNECTION=.*/DB_CONNECTION=pgsql/" \
           -e "s/DB_HOST=.*/DB_HOST=localhost/" \
           -e "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" \
           -e "s/DB_PORT=.*/DB_PORT=5432/" \
           -e "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" \
           -e "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" \
           -e "s|MEDIA_PATH=.*|MEDIA_PATH=/opt/koel_media|" \
           -e "s|FFMPEG_PATH=/usr/local/bin/ffmpeg|FFMPEG_PATH=/usr/bin/ffmpeg|" /opt/koel/.env
sed -i -e "s/^upload_max_filesize = .*/upload_max_filesize = 200M/" \
       -e "s/^post_max_size = .*/post_max_size = 200M/" \
       -e "s/^memory_limit = .*/memory_limit = 200M/" /etc/php/8.3/fpm/php.ini
msg_ok "Installed Koel"

msg_info "Set up web services"
cat <<EOF >/etc/nginx/sites-available/koel
server {
    listen          6767;
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
        internal;
        alias /opt/koel_media;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
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
rm -rf /opt/koel-${RELEASE}.zip
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
