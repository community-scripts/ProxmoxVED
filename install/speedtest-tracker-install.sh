#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: AlphaLawless
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/alexjustesen/speedtest-tracker

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  sudo \
  mc \
  git \
  gnupg2 \
  ca-certificates \
  lsb-release \
  apt-transport-https \
  nginx \
  sqlite3
msg_ok "Installed Dependencies"

msg_info "Installing Speedtest CLI"
SPEEDTEST_VERSION="1.2.0"
curl -fsSL "https://install.speedtest.net/app/cli/ookla-speedtest-${SPEEDTEST_VERSION}-linux-x86_64.tgz" -o /tmp/speedtest-cli.tgz
tar -xzf /tmp/speedtest-cli.tgz -C /usr/bin
rm -f /tmp/speedtest-cli.tgz
msg_ok "Installed Speedtest CLI"

PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="bcmath,cli,common,curl,mbstring,xml,zip,sqlite3,gd,intl,redis" setup_php

msg_info "Configuring PHP-FPM runtime directory"
mkdir -p /etc/systemd/system/php8.4-fpm.service.d/
cat > /etc/systemd/system/php8.4-fpm.service.d/override.conf <<'EOF'
[Service]
RuntimeDirectory=php
RuntimeDirectoryMode=0755
EOF
systemctl daemon-reload
msg_ok "Configured PHP-FPM runtime directory"

setup_composer
NODE_VERSION="22" setup_nodejs

msg_info "Setting up Speedtest Tracker"
RELEASE=$(curl -fsSL https://api.github.com/repos/alexjustesen/speedtest-tracker/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
cd /opt
curl -fsSL "https://github.com/alexjustesen/speedtest-tracker/archive/refs/tags/v${RELEASE}.tar.gz" -o v${RELEASE}.tar.gz
tar -xzf v${RELEASE}.tar.gz
mv speedtest-tracker-${RELEASE} speedtest-tracker
cd /opt/speedtest-tracker

CONTAINER_IP=$(hostname -I | awk '{print $1}')
APP_KEY=$(php -r "echo bin2hex(random_bytes(16));")
cat <<EOF >/opt/speedtest-tracker/.env
APP_NAME="Speedtest Tracker"
APP_ENV=production
APP_KEY=base64:$(echo -n $APP_KEY | base64)
APP_DEBUG=false
APP_URL=http://${CONTAINER_IP}

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION=sqlite
DB_DATABASE=/opt/speedtest-tracker/database/database.sqlite

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

SPEEDTEST_SCHEDULE="0 */6 * * *"
SPEEDTEST_SERVERS=
PRUNE_RESULTS_OLDER_THAN=0

DISPLAY_TIMEZONE=UTC
EOF

mkdir -p /opt/speedtest-tracker/database
touch /opt/speedtest-tracker/database/database.sqlite

export COMPOSER_ALLOW_SUPERUSER=1
$STD composer install --optimize-autoloader --no-dev

$STD npm ci
$STD npm run build

$STD php artisan key:generate --force
$STD php artisan migrate --force --seed
$STD php artisan config:clear
$STD php artisan cache:clear
$STD php artisan view:clear

chown -R www-data:www-data /opt/speedtest-tracker
chmod -R 755 /opt/speedtest-tracker/storage
chmod -R 755 /opt/speedtest-tracker/bootstrap/cache

msg_ok "Set up Speedtest Tracker"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/speedtest-tracker.service
[Unit]
Description=Speedtest Tracker Queue Worker
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /opt/speedtest-tracker/artisan queue:work --sleep=3 --tries=3 --max-time=3600
WorkingDirectory=/opt/speedtest-tracker

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now speedtest-tracker
msg_ok "Created Service"

msg_info "Setting up Scheduler"
cat <<EOF >/etc/cron.d/speedtest-tracker
* * * * * www-data cd /opt/speedtest-tracker && php artisan schedule:run >> /dev/null 2>&1
EOF
msg_ok "Set up Scheduler"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/speedtest-tracker
server {
    listen 80;
    server_name _;
    root /opt/speedtest-tracker/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/speedtest-tracker /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
systemctl reload nginx
msg_ok "Configured Nginx"

motd_ssh
customize

msg_info "Cleaning up"
rm -f /opt/v${RELEASE}.tar.gz
cleanup_lxc
msg_ok "Cleaned"
