#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://pixelfed.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  nginx \
  redis-server \
  ffmpeg \
  jpegoptim \
  optipng \
  pngquant \
  gifsicle
msg_ok "Installed Dependencies"

msg_info "Creating Pixelfed User"
useradd -rU -s /bin/bash pixelfed
usermod -aG redis pixelfed
msg_ok "Created Pixelfed User"


PG_VERSION="17" setup_postgresql
PG_DB_NAME="pixelfed" PG_DB_USER="pixelfed" setup_postgresql_db
PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="bcmath,ctype,exif,imagick,pgsql,redis,tokenizer" PHP_UPLOAD_MAX_FILESIZE="500M" PHP_POST_MAX_SIZE="500M" PHP_MAX_EXECUTION_TIME="600" setup_php
setup_composer

msg_info "Configuring Redis"
REDIS_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
sed -i "s/^# requirepass foobared/requirepass $REDIS_PASS/" /etc/redis/redis.conf
sed -i "s/^requirepass .*/requirepass $REDIS_PASS/" /etc/redis/redis.conf
systemctl restart redis-server
msg_ok "Redis configured"

msg_info "Configuring PHP-FPM Pool"
cp /etc/php/8.4/fpm/pool.d/www.conf /etc/php/8.4/fpm/pool.d/pixelfed.conf
sed -i 's/\[www\]/[pixelfed]/' /etc/php/8.4/fpm/pool.d/pixelfed.conf
sed -i 's/^user = www-data/user = pixelfed/' /etc/php/8.4/fpm/pool.d/pixelfed.conf
sed -i 's/^group = www-data/group = pixelfed/' /etc/php/8.4/fpm/pool.d/pixelfed.conf
sed -i 's|^listen = .*|listen = /run/php/php8.4-fpm-pixelfed.sock|' /etc/php/8.4/fpm/pool.d/pixelfed.conf
sed -i 's/^listen.owner = .*/listen.owner = www-data/' /etc/php/8.4/fpm/pool.d/pixelfed.conf
sed -i 's/^listen.group = .*/listen.group = www-data/' /etc/php/8.4/fpm/pool.d/pixelfed.conf
systemctl restart php8.4-fpm
msg_ok "PHP-FPM Pool configured"

fetch_and_deploy_gh_release "pixelfed" "pixelfed/pixelfed" "tarball" "latest" "/opt/pixelfed"

msg_info "Installing Pixelfed (Patience)"
cd /opt/pixelfed
cp .env.example .env
sed -i "s|APP_URL=.*|APP_URL=http://${LOCAL_IP}|" .env
sed -i "s|APP_DOMAIN=.*|APP_DOMAIN=${LOCAL_IP}|" .env
sed -i "s|ADMIN_DOMAIN=.*|ADMIN_DOMAIN=${LOCAL_IP}|" .env
sed -i "s|SESSION_DOMAIN=.*|SESSION_DOMAIN=${LOCAL_IP}|" .env
sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=pgsql|" .env
sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|" .env
sed -i "s|DB_PORT=.*|DB_PORT=5432|" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${PG_DB_NAME}|" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${PG_DB_USER}|" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${PG_DB_PASS}|" .env
sed -i "s|REDIS_HOST=.*|REDIS_HOST=127.0.0.1|" .env
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASS}|" .env
sed -i "s|REDIS_PORT=.*|REDIS_PORT=6379|" .env
sed -i "s|ACTIVITY_PUB=.*|ACTIVITY_PUB=true|" .env
sed -i "s|AP_REMOTE_FOLLOW=.*|AP_REMOTE_FOLLOW=true|" .env
sed -i "s|OAUTH_ENABLED=.*|OAUTH_ENABLED=true|" .env
echo "SESSION_SECURE_COOKIE=false" >>.env

chown -R pixelfed:pixelfed /opt/pixelfed
chmod -R 755 /opt/pixelfed
chmod -R 775 /opt/pixelfed/storage /opt/pixelfed/bootstrap/cache

export COMPOSER_ALLOW_SUPERUSER=1
cd /opt/pixelfed
$STD composer install --no-dev --no-ansi --no-interaction --optimize-autoloader

sudo -u pixelfed php artisan key:generate
sudo -u pixelfed php artisan storage:link
$STD sudo -u pixelfed php artisan migrate --force
$STD sudo -u pixelfed php artisan import:cities
$STD sudo -u pixelfed php artisan passport:keys
$STD sudo -u pixelfed php artisan route:cache
$STD sudo -u pixelfed php artisan view:cache
$STD sudo -u pixelfed php artisan config:cache
$STD sudo -u pixelfed php artisan instance:actor
$STD sudo -u pixelfed php artisan horizon:install
msg_ok "Pixelfed installed"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/pixelfed
server {
    listen 80;
    server_name _;
    root /opt/pixelfed/public;
    index index.php;

    charset utf-8;
    client_max_body_size 100M;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.4-fpm-pixelfed.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
ln -sf /etc/nginx/sites-available/pixelfed /etc/nginx/sites-enabled/pixelfed
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
systemctl enable -q --now nginx
msg_ok "Nginx configured"

msg_info "Creating Services"
cat <<'EOF' >/etc/systemd/system/pixelfed-horizon.service
[Unit]
Description=Pixelfed Horizon Queue Worker
After=network.target redis-server.service postgresql.service
Requires=redis-server.service

[Service]
Type=simple
User=pixelfed
WorkingDirectory=/opt/pixelfed
ExecStart=/usr/bin/php /opt/pixelfed/artisan horizon
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/pixelfed-scheduler.service
[Unit]
Description=Pixelfed Task Scheduler
After=network.target

[Service]
Type=oneshot
User=pixelfed
WorkingDirectory=/opt/pixelfed
ExecStart=/usr/bin/php /opt/pixelfed/artisan schedule:run
EOF

cat <<'EOF' >/etc/systemd/system/pixelfed-scheduler.timer
[Unit]
Description=Run Pixelfed Scheduler every minute

[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable -q --now pixelfed-horizon
systemctl enable -q --now pixelfed-scheduler.timer
msg_ok "Services created"

msg_info "Saving Credentials"
CREDS_FILE="/root/pixelfed.creds"
{
  echo "Pixelfed Credentials"
  echo ""
  echo "PostgreSQL"
  echo "  Database: ${PG_DB_NAME}"
  echo "  User: ${PG_DB_USER}"
  echo "  Password: ${PG_DB_PASS}"
  echo ""
  echo "Redis"
  echo "  Host: 127.0.0.1:6379"
  echo "  Password: ${REDIS_PASS}"
  echo ""
  echo "Web Interface: http://${LOCAL_IP}"
  echo "Config: /opt/pixelfed/.env"
} >"$CREDS_FILE"
msg_ok "Credentials saved to ${CREDS_FILE}"

motd_ssh
customize
cleanup_lxc
