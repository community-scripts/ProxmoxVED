#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Stroopwafe1
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://leantime.io

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PHP_VERSION=8.4
PHP_MODULE=mysql
PHP_APACHE=YES
PHP_FPM=YES

msg_info "Installing Apache2"
$STD apt-get install -y \
  apache2
msg_ok "Installed Apache2"

setup_php

msg_info "Installing Apache2 mod for PHP"
$STD apt-get install -y \
  "libapache2-mod-php${PHP_VERSION}"
msg_ok "Installed Apache2 mod"

setup_mariadb

msg_ok "Installed Dependencies"

# Template: MySQL Database
msg_info "Setting up Database"
systemctl enable -q --now mariadb
DB_NAME=leantime
DB_USER=leantime
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mysql -u root -e "CREATE DATABASE $DB_NAME;"
$STD mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password AS PASSWORD('$DB_PASS');"
$STD mysql -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "${APPLICATION} Credentials"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo "Database Name: $DB_NAME"
} >>~/"$APPLICATION".creds
msg_ok "Set up Database"

# Setup App
msg_info "Setup ${APPLICATION}"
APACHE_LOG_DIR=/var/log/apache2
RELEASE=$(curl -fsSL https://api.github.com/repos/Leantime/leantime/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL -o "${RELEASE}.tar.gz" "https://github.com/Leantime/leantime/releases/download/${RELEASE}/Leantime-${RELEASE}.tar.gz"
mkdir -p "/opt/${APPLICATION}"
mkdir -p /etc/apache2/sites-enabled
tar xf "${RELEASE}.tar.gz" --strip-components=1 -C "/opt/${APPLICATION}"
chown -R www-data:www-data "/opt/${APPLICATION}"
chmod -R 750 "/opt/${APPLICATION}"

cat <<EOF >/etc/apache2/sites-enabled/000-default.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /opt/${APPLICATION}/public
  DirectoryIndex index.php index.html index.cgi index.pl index.xhtml
  Options +ExecCGI

  <Directory /opt/${APPLICATION}/>
    Options FollowSymLinks
    Require all granted
    AllowOverride All
  </Directory>

  <Location />
    Require all granted
  </Location>

  ErrorLog ${APACHE_LOG_DIR}/error.log
  CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

mv "/opt/${APPLICATION}/config/sample.env" "/opt/${APPLICATION}/config/.env"
sed -i -e "s|^LEAN_DB_DATABASE.*|LEAN_DB_DATABASE = '$DB_NAME'|" \
  -e "s|^LEAN_DB_USER.*|LEAN_DB_USER = '$DB_USER'|" \
  -e "s|^LEAN_DB_PASSWORD.*|LEAN_DB_PASSWORD = '$DB_PASS'|" \
  -e "s|^LEAN_SESSION_PASSWORD.*|LEAN_SESSION_PASSWORD = '$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)'|" \
  "/opt/${APPLICATION}/config/.env"

a2enmod -q proxy_fcgi setenvif rewrite
a2enconf -q "php${PHP_VERSION}-fpm"

sed -i -e "s/^;extension.\(curl\|fileinfo\|gd\|intl\|ldap\|mbstring\|exif\|mysqli\|odbc\|openssl\|pdo_mysql\)/extension=\1/g" "/etc/php/${PHP_VERSION}/apache2/php.ini"

systemctl restart apache2

echo "${RELEASE}" >/opt/"${APPLICATION}"_version.txt
msg_ok "Setup ${APPLICATION}"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f "${RELEASE}".tar.gz
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
