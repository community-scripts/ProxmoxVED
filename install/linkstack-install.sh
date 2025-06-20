#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://linkstack.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
    software-properties-common \
    ca-certificates \
    lsb-release \
    apt-transport-https \
    apache2
    unzip
msg_ok "Installed dependencies"

PHP_VERSION="8.2" PHP_MODULE="sqlite3, mysql, fileinfo" PHP_APACHE="YES" install_php

msg_info "Installing LinkStack"
$STD a2enmod rewrite

ZIP_URL="https://github.com/linkstackorg/linkstack/releases/latest/download/linkstack.zip"
ZIP_FILE="/tmp/linkstack.zip"
curl -fsSL -o "$ZIP_FILE" "$ZIP_URL"
unzip -q "$ZIP_FILE" -d /var/www/html/linkstack
chown -R www-data:www-data /var/www/html/linkstack
chmod -R 755 /var/www/html/linkstack

cat <<EOF > /etc/apache2/sites-available/linkstack.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/linkstack/linkstack
    ErrorLog /var/log/apache2/linkstack-error.log
    CustomLog /var/log/apache2/linkstack-access.log combined
    <Directory /var/www/html/linkstack/linkstack>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
$STD a2dissite 000-default.conf
$STD a2ensite linkstack.conf
$STD systemctl restart apache2
msg_ok "Installed LinkStack"

motd_ssh
customize

msg_info "Cleaning up"
$STD rm -f "$ZIP_FILE"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
