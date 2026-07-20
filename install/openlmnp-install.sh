#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: manganate006
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/manganate006/openlmnp

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  sqlite3 \
  unzip \
  rsync
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="bcmath,intl,gd,zip,sqlite3" setup_php
setup_composer

fetch_and_deploy_gh_release "openlmnp" "manganate006/openlmnp" "tarball"

msg_info "Configuring OpenLMNP"
cd /opt/openlmnp || exit

# Generate a valid Laravel APP_KEY without artisan (vendor/ is installed by composer below)
APP_KEY="base64:$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
cat <<EOF >/opt/openlmnp/.env
APP_NAME=OpenLMNP
APP_ENV=production
APP_KEY=${APP_KEY}
APP_DEBUG=false
APP_URL=http://${LOCAL_IP}

LOG_CHANNEL=stack
LOG_LEVEL=warning

DB_CONNECTION=sqlite
DB_DATABASE=/opt/openlmnp/database/database.sqlite

SESSION_DRIVER=file
SESSION_LIFETIME=120
CACHE_STORE=file
QUEUE_CONNECTION=sync

APP_LOCALE=fr
APP_FALLBACK_LOCALE=en

MAIL_MAILER=log

MCP_ENABLED=false
EOF

export COMPOSER_ALLOW_SUPERUSER=1
$STD /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction
$STD npm install --no-audit --no-fund
$STD npm run build

mkdir -p database storage/app/{public,data} storage/{logs,framework/{sessions,views,cache}}
touch database/database.sqlite
chmod 775 database/database.sqlite

$STD php artisan storage:link
$STD php artisan migrate --force
$STD php artisan db:seed --force
$STD php artisan optimize
msg_ok "Configured OpenLMNP"

msg_info "Securing Admin Account"
ADMIN_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
# Replace the seeded demo password with a random one (password is cast as 'hashed')
$STD php artisan tinker --execute="\$u = \App\Models\User::query()->orderBy('id')->first(); if (\$u) { \$u->password = '${ADMIN_PASS}'; \$u->save(); }"
{
  echo "OpenLMNP — identifiants administrateur"
  echo "Email    : demo@openlmnp.fr"
  echo "Password : ${ADMIN_PASS}"
  echo ""
  echo "Changez-les après la première connexion."
} >/opt/openlmnp/admin_credentials.txt
chmod 600 /opt/openlmnp/admin_credentials.txt
msg_ok "Secured Admin Account (credentials in /opt/openlmnp/admin_credentials.txt)"

chown -R www-data:www-data /opt/openlmnp
chmod -R 775 /opt/openlmnp/storage /opt/openlmnp/database /opt/openlmnp/bootstrap/cache
chmod 640 /opt/openlmnp/.env
chmod 600 /opt/openlmnp/admin_credentials.txt

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/openlmnp
server {
    listen 80;
    server_name _;
    root /opt/openlmnp/public;
    index index.php;

    client_max_body_size 20M;
    charset utf-8;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    gzip on;
    gzip_types application/javascript application/x-javascript text/javascript text/plain text/css application/json application/xml image/svg+xml;
    gzip_min_length 1000;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /index.php {
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    location ~ \.php$ {
        return 403;
    }

    location ~ /\.ht {
        deny all;
    }

    error_log /var/log/nginx/openlmnp_error.log;
    access_log /var/log/nginx/openlmnp_access.log;
}
EOF

$STD apt install -y nginx
ln -sf /etc/nginx/sites-available/openlmnp /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
msg_ok "Configured Nginx"

msg_info "Setting up Cron"
cat <<'EOF' >/etc/cron.d/openlmnp
* * * * * www-data cd /opt/openlmnp && php artisan schedule:run >> /dev/null 2>&1
EOF
msg_ok "Set up Cron"

msg_info "Enabling Services"
systemctl enable -q --now php8.4-fpm nginx
msg_ok "Enabled Services"

motd_ssh
customize
cleanup_lxc
