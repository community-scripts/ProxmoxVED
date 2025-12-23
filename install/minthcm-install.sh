#!/usr/bin/env bash

# Copyright (c) 2021-2025 minthcm
# Author: MintHCM
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/minthcm/minthcm
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PHP_APACHE="YES" PHP_VERSION="8.2" PHP_MODULE="mysql,cli,redis" PHP_FPM="YES" setup_php
setup_composer

msg_info "Enabling Apache modules (rewrite, headers)"
$STD a2enmod rewrite
$STD a2enmod headers
msg_ok "Enabled Apache modules (rewrite, headers)"

fetch_and_deploy_gh_release "MintHCM" "minthcm/minthcm" "tarball" "latest" "/var/www/MintHCM"

msg_info "Configuring PHP and Apache2 for MintHCM"
mkdir -p /etc/php/8.2/mods-available
cp /var/www/MintHCM/docker/config/000-default.conf /etc/apache2/sites-available/000-default.conf
cp /var/www/MintHCM/docker/config/php-minthcm.ini /etc/php/8.2/mods-available/php-minthcm.ini
mkdir -p "/etc/php/8.2/cli/conf.d" "/etc/php/8.2/apache2/conf.d"
ln -s "/etc/php/8.2/mods-available/php-minthcm.ini" "/etc/php/8.2/cli/conf.d/20-minthcm.ini"
ln -s "/etc/php/8.2/mods-available/php-minthcm.ini" "/etc/php/8.2/apache2/conf.d/20-minthcm.ini"
msg_ok "Configured PHP and Apache2 for MintHCM"

msg_info "Setting ownership and permissions for MintHCM directory"
chown -R www-data:www-data /var/www/MintHCM
find /var/www/MintHCM -type d -exec chmod 755 {} \;
find /var/www/MintHCM -type f -exec chmod 644 {} \;
msg_ok "Set up ownership and permissions for MintHCM directory"

msg_info "Restarting Apache2"
$STD systemctl restart apache2
msg_ok "Restarted Apache2"

msg_info "Setting up Elasticsearch"
setup_deb822_repo \
  "elasticsearch" \
  "https://artifacts.elastic.co/GPG-KEY-elasticsearch" \
  "https://artifacts.elastic.co/packages/7.x/apt" \
  "stable" \
  "main"
$STD apt install -y elasticsearch

echo "-Xms2g" >>/etc/elasticsearch/jvm.options
echo "-Xmx2g" >>/etc/elasticsearch/jvm.options

$STD /usr/share/elasticsearch/bin/elasticsearch-plugin install ingest-attachment -b

systemctl enable -q --now elasticsearch
msg_ok "Set up Elasticsearch"

msg_info "Setting up MariaDB"
setup_mariadb
$STD mariadb -u root -e "SET GLOBAL sql_mode='STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'";
msg_ok "Set up MariaDB"

msg_info "Configuring database for MintHCM"

DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mariadb -u root -e "CREATE USER 'minthcm'@'localhost' IDENTIFIED BY '${DB_PASS}';"
$STD mariadb -u root -e "GRANT ALL ON *.* TO 'minthcm'@'localhost'; FLUSH PRIVILEGES;"
msg_ok "Configured MariaDB for MintHCM"

msg_info "Downloading generate_config.php script"
mkdir -p /var/www/script
cp /var/www/MintHCM/docker/script/generate_config.php /var/www/script/generate_config.php
chown -R www-data:www-data /var/www/script
msg_ok "Downloading generate_config.php script"

cp /var/www/MintHCM/docker/.env /var/www/script/.env
sed -i 's/^DB_HOST=.*/DB_HOST=localhost/' /var/www/script/.env
sed -i 's/^DB_USER=.*/DB_USER=minthcm/' /var/www/script/.env
sed -i "s/^DB_PASS=.*/DB_PASS=${DB_PASS}/" /var/www/script/.env
sed -i 's/^ELASTICSEARCH_HOST=.*/ELASTICSEARCH_HOST=localhost/' /var/www/script/.env

{
  echo "MintHCM DB Credentials"
  echo "MariaDB User: minthcm"
  echo "MariaDB Password: $DB_PASS"
} >>~/minthcm.creds

msg_info "Generating MintHCM configuration file (configMint4)"
set -a
source /var/www/script/.env
set +a
php /var/www/script/generate_config.php || msg_error "Failed to execute generate_config.php"

if [[ ! -f /var/www/MintHCM/configMint4 ]]; then
  msg_error "Error: Failed to generate configMint4 - please check the configuration"
  exit 1
fi
msg_ok "Generated MintHCM configuration file (configMint4)"

msg_info "Starting MintHCM installation..."
cd /var/www/MintHCM && su -s /bin/bash -c 'php /var/www/MintHCM/MintCLI install < /var/www/MintHCM/configMint4' www-data

if [[ $? -ne 0 ]]; then
  msg_error "Error: MintHCM installation failed - please check logs"
else
  msg_ok "MintHCM installation completed!"
  msg_info "Configuring cron for MintHCM"
  printf "*    *    *    *    *     cd /var/www/MintHCM/legacy; php -f cron.php > /dev/null 2>&1\n" > /var/spool/cron/crontabs/www-data \
    || msg_error "Failed to configure cron for www-data"
  service cron start || msg_error "Failed to start cron service"
  rm -f /var/www/MintHCM/configMint4
fi


motd_ssh
customize
cleanup_lxc
