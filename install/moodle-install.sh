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

msg_info "Installing Web & DB stack"
$STD apt-get install -y apache2 mariadb-server git unzip \
  php libapache2-mod-php \
  php-mysql php-zip php-xml php-gd php-curl \
  php-intl php-mbstring php-soap php-bcmath php-ldap
msg_ok "Installed Web & DB stack"

msg_info "Preparing database"
DB_NAME="moodle"
DB_USER="moodleuser"
DB_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c24)"
$STD mysql -u root -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$STD mysql -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
$STD mysql -u root -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,CREATE TEMPORARY TABLES,DROP,INDEX,ALTER ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "Moodle DB Credentials"
  echo "DB Name: ${DB_NAME}"
  echo "DB User: ${DB_USER}"
  echo "DB Pass: ${DB_PASS}"
} >>~/"moodle.creds"
msg_ok "Database ready"

msg_ok "Selecting Moodle branch"
REMOTE_BRANCHES="$(git ls-remote --heads https://github.com/moodle/moodle.git 'MOODLE_*_STABLE' | awk -F'refs/heads/' '{print $2}' | sort -V)"
echo "Available stable branches:"
echo "${REMOTE_BRANCHES}"
echo -n "Enter branch to install [default MOODLE_500_STABLE]: "
read -r MOODLE_BRANCH
MOODLE_BRANCH="${MOODLE_BRANCH:-MOODLE_500_STABLE}"
if ! echo "${REMOTE_BRANCHES}" | grep -qx "${MOODLE_BRANCH}"; then
  msg_error "Branch ${MOODLE_BRANCH} not found among remotes"
  exit 1
fi
msg_ok "Selected ${MOODLE_BRANCH}"

msg_info "Cloning Moodle (shallow)"
install -d -m 0755 /var/www
$STD rm -rf /var/www/moodle
$STD git clone --depth 1 --branch "${MOODLE_BRANCH}" https://github.com/moodle/moodle.git /var/www/moodle
msg_ok "Cloned Moodle ${MOODLE_BRANCH}"

msg_info "Setting permissions and data directory"
install -d -m 0770 -o www-data -g www-data /var/moodledata
$STD chown -R www-data:www-data /var/www/moodle
$STD find /var/www/moodle -type d -exec chmod 02775 {} \;
$STD find /var/www/moodle -type f -exec chmod 0644 {} \;
msg_ok "Permissions set"

msg_info "PHP tuning (CLI and Apache)"
PHPVER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" || true
if [[ -z "$PHPVER" ]]; then
  PHPVER="$(ls -1d /etc/php/* 2>/dev/null | awk -F'/' '{print $4}' | head -n1)"
fi
if [[ -z "$PHPVER" ]]; then
  msg_error "Unable to determine PHP version path under /etc/php"
  exit 1
fi
for sapi in apache2 cli; do
  install -d -m 0755 "/etc/php/${PHPVER}/${sapi}/conf.d"
  {
    echo "max_input_vars=5000"
    echo "memory_limit=256M"
  } >"/etc/php/${PHPVER}/${sapi}/conf.d/99-moodle.ini"
done
$STD systemctl reload apache2
msg_ok "PHP tuned"

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

msg_info "Preparing installer inputs"
IPV4="$(hostname -I | awk '{print $1}')"
WWWROOT="http://${IPV4}"
FQDN="$(hostname -f 2>/dev/null || true)"
if [[ "$FQDN" =~ \. ]]; then
  DEFAULT_ADMIN_EMAIL="admin@${FQDN}"
else
  DEFAULT_ADMIN_EMAIL="admin@example.com"
fi
ADMIN_EMAIL="${MOODLE_ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}"
if ! printf '%s' "$ADMIN_EMAIL" | grep -Eq '^[^@]+@[^@]+\.[^@]+$'; then
  ADMIN_EMAIL="admin@example.com"
fi
SITE_FULLNAME="Moodle Site"
SITE_SHORTNAME="Moodle"
ADMIN_USER="admin"
ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c20)"
msg_ok "Installer inputs prepared"

msg_info "Running non-interactive Moodle CLI installer (MariaDB driver)"
$STD /usr/bin/php /var/www/moodle/admin/cli/install.php \
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
  --fullname="${SITE_FULLNAME}" \
  --shortname="${SITE_SHORTNAME}" \
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