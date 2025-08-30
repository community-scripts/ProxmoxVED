#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: EEJoshua
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.moodle.org/500/en/Git_for_Administrators

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Install PHP (Apache) + required modules"
$STD apt-get install -y git
PHP_VERSION="8.2"
PHP_APACHE="YES"
PHP_FPM="NO"
PHP_MODULE="bcmath,curl,gd,intl,mbstring,opcache,readline,xml,zip,mysql,soap,ldap"
PHP_MEMORY_LIMIT="256M"
export PHP_VERSION PHP_APACHE PHP_FPM PHP_MODULE PHP_MEMORY_LIMIT
setup_php
msg_ok "PHP ready"

msg_info "Install MariaDB"
MARIADB_VERSION="latest"
export MARIADB_VERSION
setup_mariadb
msg_ok "MariaDB ready"

msg_info "Create Moodle database"
DB_NAME="moodle"
DB_USER="moodleuser"
DB_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c24)"
$STD mariadb -u root -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$STD mariadb -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
$STD mariadb -u root -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,CREATE TEMPORARY TABLES,DROP,INDEX,ALTER ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "Moodle DB Credentials"
  echo "DB Name: ${DB_NAME}"
  echo "DB User: ${DB_USER}"
  echo "DB Pass: ${DB_PASS}"
} >>~/"moodle.creds"
msg_ok "Database ready"

msg_info "Deploying Moodle (latest GitHub release)"
install -d -m 0755 /var/www
$STD rm -rf /var/www/moodle
fetch_and_deploy_gh_release "moodle" "moodle/moodle" "tarball" "latest" "/var/www/moodle"
$STD chown -R www-data:www-data /var/www/moodle
install -d -m 0770 -o www-data -g www-data /var/moodledata
msg_ok "Code deployed"

msg_info "Configuring Apache"
cat >/etc/apache2/sites-available/moodle.conf <<'EOF'
<VirtualHost *:80>
    ServerName _
    DocumentRoot /var/www/moodle
    <Directory /var/www/moodle>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${APACHE_LOG_DIR}/moodle_error.log
    CustomLog ${APACHE_LOG_DIR}/moodle_access.log combined
</VirtualHost>
EOF
$STD a2enmod rewrite
$STD a2dissite 000-default.conf
$STD a2ensite moodle.conf
$STD systemctl reload apache2
msg_ok "Apache configured"

msg_info "Apply PHP tunables"
PHPVER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" 2>/dev/null || true
[[ -z "$PHPVER" ]] && PHPVER="$(ls -1d /etc/php/* 2>/dev/null | awk -F'/' '{print $4}' | head -n1)"
for sapi in apache2 cli; do
  install -d -m 0755 "/etc/php/${PHPVER}/${sapi}/conf.d"
  {
    echo "max_input_vars=5000"
    echo "memory_limit=256M"
  } >"/etc/php/${PHPVER}/${sapi}/conf.d/99-moodle.ini"
done
$STD systemctl reload apache2
msg_ok "PHP tuned"

msg_info "Run Moodle CLI installer"
IPV4="$(hostname -I | awk '{print $1}')"
WWWROOT="http://${IPV4}"
DEFAULT_ADMIN_EMAIL="admin@example.com"
ADMIN_EMAIL="${MOODLE_ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}"
ADMIN_USER="admin"
ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c20)"

msg_info "Running non-interactive Moodle CLI installer (MariaDB driver)"
$STD runuser -u www-data -- /usr/bin/php /var/www/moodle/admin/cli/install.php \
  --chmod=2775 \
  --lang=en \
  --wwwroot="${WWWROOT}" \
  --dataroot="/var/moodledata" \
  --dbtype="mariadb" \
  --dbhost="localhost" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASS}" \
  --dbport="" \
  --fullname="Moodle Site" \
  --shortname="Moodle" \
  --summary="Self-hosted Moodle (${MOODLE_BRANCH})" \
  --adminuser="${ADMIN_USER}" \
  --adminpass="${ADMIN_PASS}" \
  --adminemail="${ADMIN_EMAIL}" \
  --agree-license \
  --non-interactive
{
  echo ""
  echo "Moodle Admin Credentials"
  echo "User: ${ADMIN_USER}"
  echo "Pass: ${ADMIN_PASS}"
  echo "Email: ${ADMIN_EMAIL}"
  echo "URL : ${WWWROOT}"
  echo "Branch: ${MOODLE_BRANCH}"
} >>~/"moodle.creds"
msg_ok "CLI installer completed"

msg_info "Enabling cron"
echo '* * * * * www-data /usr/bin/php -f /var/www/moodle/admin/cli/cron.php >/dev/null 2>&1' >/etc/cron.d/moodle
$STD chmod 0644 /etc/cron.d/moodle
msg_ok "Cron enabled"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
