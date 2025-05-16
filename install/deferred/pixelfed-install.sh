#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck
# Co-Author: MickLesk (Canbiz)
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
$STD apt-get install -y \
    build-essential \
    gpg \
    curl \
    sudo \
    git \
    gnupg2 \
    ca-certificates \
    lsb-release \
    php8.3-{fpm,bcmath,ctype,curl,exif,gd,iconv,intl,mbstring,redis,tokenizer,xml,zip,pgsql,pdo-pgsql,bz2,sqlite3} \
    composer \
    redis \
    ffmpeg \
    jpegoptim \
    optipng \
    pngquant \
    make \
    mc
msg_ok "Installed Dependencies"

msg_info "Configure Redis Socket"
REDIS_PASS="$(openssl rand -base64 18 | cut -c1-13)"
sed -i 's/^port .*/port 0/' /etc/redis/redis.conf
sed -i "s/^# requirepass foobared/requirepass $REDIS_PASS/" /etc/redis/redis.conf
sed -i 's|^# unixsocket .*|unixsocket /run/redis/redis.sock|' /etc/redis/redis.conf
sed -i 's/^# unixsocketperm .*/unixsocketperm 770/' /etc/redis/redis.conf
systemctl restart redis
msg_ok "Redis Socket configured"

msg_info "Add pixelfed user"
useradd -rU -s /bin/bash pixelfed
msg_ok "Pixelfed User Added"

msg_info "Configure PHP-FPM for Pixelfed"
cp /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/pixelfed.conf
sed -i 's/\[www\]/\[pixelfed\]/' /etc/php/8.3/fpm/pool.d/pixelfed.conf
sed -i 's/^user = www-data/user = pixelfed/' /etc/php/8.3/fpm/pool.d/pixelfed.conf
sed -i 's/^group = www-data/group = pixelfed/' /etc/php/8.3/fpm/pool.d/pixelfed.conf
sed -i 's|^listen = .*|listen = /run/php-fpm/pixelfed.sock|' /etc/php/8.3/fpm/pool.d/pixelfed.conf
systemctl restart php8.3-fpm
msg_ok "successfully configured PHP-FPM"

msg_info "Setup Postgres Database"
DB_NAME=pixelfed_db
DB_USER=pixelfed_user
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" >/etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql-17
sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE template0;"
sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;"
sudo -u postgres psql -c "GRANT CREATE ON SCHEMA public TO $DB_USER;"
echo "" >>~/pixelfed.creds
echo -e "Pixelfed Database Name: $DB_NAME" >>~/pixelfed.creds
echo -e "Pixelfed Database User: $DB_USER" >>~/pixelfed.creds
echo -e "Pixelfed Database Password: $DB_PASS" >>~/pixelfed.creds
#export $(cat /opt/pixelfed/.env |grep "^[^#]" | xargs)
msg_ok "Set up PostgreSQL Database successfully"

msg_info "Installing Pixelfed (Patience)"
RELEASE=$(curl -s https://api.github.com/repos/pixelfed/pixelfed/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/pixelfed/pixelfed/archive/refs/tags/${RELEASE}.zip"
unzip -q ${RELEASE}.zip
mv pixelfed-${RELEASE:1} /opt/pixelfed
rm -R ${RELEASE}.zip
cd /opt/pixelfed
chown -R www-data:www-data /opt/pixelfed/storage
chmod -R 775 /opt/pixelfed/storage
chown -R pixelfed:pixelfed /opt/pixelfed/storage
chmod -R 775 /opt/pixelfed/storage
chown -R www-data:www-data /opt/pixelfed
chmod -R 755 /opt/pixelfed
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --no-ansi --no-interaction --optimize-autoloader

msg_info "Setup envoirement & PHP Database Migration"
cp .env.example .env
sed -i "s/DB_CONNECTION=.*/DB_CONNECTION=pgsql/" .env
sed -i "s/DB_PORT=.*/DB_PORT=5432/" .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" .env
sed -i "s/REDIS_HOST=.*/REDIS_HOST=127.0.0.1/" .env
sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=$REDIS_PASS/" .env
sed -i "s/APP_URL=.*/APP_URL=http:\/\/localhost/" .env # localhost URL

php artisan key:generate
php artisan storage:link
php artisan migrate --force
php artisan import:cities
php artisan instance:actor
php artisan passport:keys
php artisan route:cache
php artisan view:cache
sed -i 's/^post_max_size = .*/post_max_size = 100M/' /etc/php/8.3/fpm/php.ini
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.3/fpm/php.ini
sed -i 's/^max_execution_time = .*/max_execution_time = 600/' /etc/php/8.3/fpm/php.ini
systemctl restart php8.3-fpm

msg_ok "Pixelfed successfully set up"

msg_info "Creating Services"
cat <<EOF >/etc/nginx/sites-available/pixelfed.conf
server {
    listen 80;
    server_name localhost;  # Nutzung von localhost
    root /opt/pixelfed/public;

    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    client_max_body_size 20M;
}
EOF

ln -s /etc/nginx/sites-available/pixelfed.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

cat <<EOF >/etc/systemd/system/pixelfed-horizon.service
[Unit]
Description=Pixelfed Horizon
After=network.target
Requires=php8.3-fpm
Requires=redis

[Service]
User=www-data
WorkingDirectory=/opt/pixelfed
ExecStart=/usr/bin/php /opt/pixelfed/artisan horizon
Restart=always

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/pixelfed-scheduler.service
[Unit]
Description=Pixelfed Scheduler
After=network.target

[Service]
User=www-data
ExecStart=/usr/bin/php /opt/pixelfed/artisan schedule:run
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now pixelfed-scheduler
systemctl enable --now pixelfed-horizon
msg_ok "Created Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
