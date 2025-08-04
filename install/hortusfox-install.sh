#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/danielbrendel/hortusfox-web

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y apache2
msg_ok "Installed Dependencies"

PHP_MODULE="exif,pcntl,mysql" PHP_APACHE="YES" PHP_FPM="NO" PHP_VERSION="8.3" setup_php
setup_mariadb
setup_composer

msg_info "Setting up database"
DB_NAME=hortusfox
DB_USER=hortusfox
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mariadb -u root -e "CREATE DATABASE $DB_NAME;"
$STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
$STD mariadb -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "HortusFox Database Credentials"
  echo "Database: $DB_NAME"
  echo "Username: $DB_USER"
  echo "Password: $DB_PASS"
} >>~/hortusfox.creds
msg_ok "Set up database"

fetch_and_deploy_gh_release "hortusfox-web" "danielbrendel/hortusfox-web"

msg_info "Configuring .env"
cp /opt/hortusfox-web/.env.example /opt/hortusfox-web/.env
sed -i "s|^DB_HOST=.*|DB_HOST=localhost|" /opt/hortusfox-web/.env
sed -i "s|^DB_USER=.*|DB_USER=$DB_USER|" /opt/hortusfox-web/.env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" /opt/hortusfox-web/.env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" /opt/hortusfox-web/.env
sed -i "s|^DB_ENABLE=.*|DB_ENABLE=true|" /opt/hortusfox-web/.env
sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=Europe/Berlin|" /opt/hortusfox-web/.env
msg_ok ".env configured"

msg_info "Installing PHP dependencies (composer)"
cd /opt/hortusfox-web
$STD composer install --no-dev --optimize-autoloader
msg_ok "PHP dependencies installed"

msg_info "Running DB migration"
php asatru migrate:fresh
msg_ok "Migration finished"

msg_info "Configuring Apache vHost"
cat <<EOF >/etc/apache2/sites-available/hortusfox.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /opt/hortusfox-web/public
    <Directory /opt/hortusfox-web/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/hortusfox_error.log
    CustomLog \${APACHE_LOG_DIR}/hortusfox_access.log combined
</VirtualHost>
EOF
$STD a2dissite 000-default
$STD a2ensite hortusfox
$STD a2enmod rewrite
systemctl restart apache2
msg_ok "Apache configured"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
