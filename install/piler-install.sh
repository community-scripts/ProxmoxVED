#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.mailpiler.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  openssl \
  libtre5 \
  catdoc \
  poppler-utils \
  unrtf \
  tnef \
  memcached \
  sysstat \
  python3 \
  python3-mysqldb \
  ca-certificates \
  gnupg
msg_ok "Installed Dependencies"


setup_mariadb
MARIADB_DB_NAME="piler" MARIADB_DB_USER="piler" setup_mariadb_db
PHP_VERSION="8.3" PHP_FPM="YES" PHP_MODULE="ldap,gd,memcached,pdo,mysql,curl,zip" setup_php

msg_info "Installing Manticore Search"
cd /tmp
wget -q https://repo.manticoresearch.com/manticore-repo.noarch.deb
$STD dpkg -i /tmp/manticore-repo.noarch.deb
$STD apt update
$STD apt install -y manticore manticore-columnar-lib manticore-extra
rm -f /tmp/manticore-repo.noarch.deb
mkdir -p /var/run/manticore
chown manticore:manticore /var/run/manticore
$STD systemctl stop manticore
$STD systemctl disable manticore
msg_ok "Installed Manticore Search"

fetch_and_deploy_gh_release "piler" "jsuto/piler" "binary" "latest" "/tmp" "piler_*-noble-*_amd64.deb"
fetch_and_deploy_gh_release "piler-webui" "jsuto/piler" "binary" "latest" "/tmp" "piler-webui_*-noble-*_amd64.deb"

msg_info "Configuring Piler Database"
$STD mariadb -u root "${MARIADB_DB_NAME}" </usr/share/piler/db-mysql.sql 2>/dev/null || true
msg_ok "Configured Piler Database"

msg_info "Configuring Piler"
cat <<EOF >/etc/piler/piler.conf
hostid=piler.${LOCAL_IP}.nip.io
update_counters_to_memcached=1

mysql_hostname=localhost
mysql_database=${MARIADB_DB_NAME}
mysql_username=${MARIADB_DB_USER}
mysql_password=${MARIADB_DB_PASS}
mysql_socket=/var/run/mysqld/mysqld.sock

archive_dir=/var/piler/store

listen_addr=0.0.0.0
listen_port=25

memcached_servers=127.0.0.1

spam_header_line=X-Spam-Status: Yes

verbosity=1
EOF

chown piler:piler /etc/piler/piler.conf
chmod 640 /etc/piler/piler.conf
mkdir -p /var/piler/store /var/piler/tmp
chown -R piler:piler /var/piler
chmod 750 /var/piler
# Create symlink for MySQL socket compatibility
ln -sf /var/run/mysqld/mysqld.sock /tmp/mysql.sock 2>/dev/null || true
msg_ok "Configured Piler"

msg_info "Configuring Manticore Search"
cat <<EOF >/etc/manticoresearch/manticore.conf
searchd {
  listen = 9306:mysql
  listen = 9312
  listen = 9308:http
  log = /var/log/manticore/searchd.log
  query_log = /var/log/manticore/query.log
  pid_file = /run/manticore/searchd.pid
  binlog_path = /var/lib/manticore/data
}

source piler1 {
  type = mysql
  sql_host = localhost
  sql_user = ${MARIADB_DB_USER}
  sql_pass = ${MARIADB_DB_PASS}
  sql_db = ${MARIADB_DB_NAME}
  sql_port = 3306

  sql_query = SELECT id, \\\`from\\\` as from_addr, subject, CAST(sent AS UNSIGNED) as sent FROM metadata WHERE deleted=0
  sql_attr_timestamp = sent
}

index piler1 {
  source = piler1
  path = /var/piler/manticore/piler1
  min_word_len = 1
  charset_table = 0..9, A..Z->a..z, a..z, U+00E1, U+00E9
}

index tag1 {
  type = rt
  path = /var/piler/manticore/tag1
  rt_field = tag
  rt_attr_uint = uid
}

index note1 {
  type = rt
  path = /var/piler/manticore/note1
  rt_field = note
  rt_attr_uint = uid
}
EOF

cat > /etc/tmpfiles.d/manticore.conf <<'TMPEOF'
d /run/manticore 0755 manticore manticore -
TMPEOF

mkdir -p /var/log/manticore
mkdir -p /var/lib/manticore/data
chown -R manticore:manticore /var/log/manticore /var/lib/manticore
chmod 775 /var/piler/manticore
chown piler:manticore /var/piler/manticore
msg_ok "Configured Manticore Search"

msg_info "Building Manticore Search Indexes"
$STD systemctl start manticore
sleep 2
$STD indexer --config /etc/manticoresearch/manticore.conf piler1
$STD systemctl restart manticore
msg_ok "Built Manticore Search Indexes"

msg_info "Creating Piler Service"
cat <<EOF >/etc/systemd/system/piler.service
[Unit]
Description=Piler Email Archiving
After=network.target mysql.service manticore.service memcached.service
Requires=mysql.service
Wants=manticore.service

[Service]
Type=simple
User=piler
Group=piler
RuntimeDirectory=piler
ExecStart=/usr/sbin/piler -c /etc/piler/piler.conf -d
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reload
$STD systemctl enable --now manticore
$STD systemctl enable --now memcached
$STD systemctl enable --now piler
msg_ok "Created Piler Service"

msg_info "Configuring PHP-FPM Pool"
cp /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/piler.conf
sed -i 's/\[www\]/[piler]/' /etc/php/8.3/fpm/pool.d/piler.conf
sed -i 's/^user = www-data/user = piler/' /etc/php/8.3/fpm/pool.d/piler.conf
sed -i 's/^group = www-data/group = piler/' /etc/php/8.3/fpm/pool.d/piler.conf
sed -i 's|^listen = .*|listen = /run/php/php8.3-fpm-piler.sock|' /etc/php/8.3/fpm/pool.d/piler.conf
$STD systemctl restart php8.3-fpm
msg_ok "Configured PHP-FPM Pool"

msg_info "Configuring Piler Web GUI"
# Ensure MariaDB user has correct password before writing config
$STD mariadb -u root -e "ALTER USER '$MARIADB_DB_USER'@'localhost' IDENTIFIED BY '$MARIADB_DB_PASS';"
$STD mariadb -u root -e "GRANT ALL ON \`$MARIADB_DB_NAME\`.* TO '$MARIADB_DB_USER'@'localhost';"
$STD mariadb -u root -e "FLUSH PRIVILEGES;"

# Always ensure config-site.php matches generated credentials
if [ -f /var/piler/www/config-site.php ]; then
  cp -f /var/piler/www/config-site.php /var/piler/www/config-site.php.bak
fi

cat <<EOF >/var/piler/www/config-site.php
<?php
\$config['SITE_NAME'] = 'Piler Email Archive';
\$config['SITE_URL'] = 'http://${LOCAL_IP}';

\$config['DB_DRIVER'] = 'mysql';
\$config['DB_HOSTNAME'] = 'localhost';
\$config['DB_DATABASE'] = '${MARIADB_DB_NAME}';
\$config['DB_USERNAME'] = '${MARIADB_DB_USER}';
\$config['DB_PASSWORD'] = '${MARIADB_DB_PASS}';

\$config['SPHINX_DATABASE'] = 'mysql:host=127.0.0.1;port=9306;charset=utf8mb4';

\$config['ENABLE_SAAS'] = 0;
\$config['SESSION_NAME'] = 'piler_session';
\$config['SITE_KEYWORDS'] = 'piler, email archive';
\$config['SITE_DESCRIPTION'] = 'Piler email archiving';

\$config['SMTP_DOMAIN'] = '${LOCAL_IP}';
\$config['SMTP_FROMADDR'] = 'no-reply@${LOCAL_IP}';

\$config['ADMIN_EMAIL'] = 'admin@local';
\$config['ADMIN_PASSWORD'] = '\$1\$PXDhp7Bo\$KlEEURhLLphAEa4w.lj1N0';

\$config['MEMCACHED_ENABLED'] = 1;
\$config['MEMCACHED_PREFIX'] = 'piler';
\$config['MEMCACHED_TTL'] = 3600;

\$config['DIR_BASE'] = '/var/piler/www';
\$config['DIR_ATTACHMENT'] = '/var/piler/store';

\$config['DEFAULT_RETENTION_DAYS'] = 2557;
\$config['RESTRICTED_AUDITOR'] = 0;

\$config['ENABLE_LDAP_AUTH'] = 0;
\$config['ENABLE_IMAP_AUTH'] = 0;
\$config['ENABLE_POP3_AUTH'] = 0;
\$config['ENABLE_SSO_AUTH'] = 0;

\$config['HEADER_LINE_TO_HIDE'] = 'X-Envelope-To:';
?>
EOF

chown -R piler:piler /var/piler/www
chmod 755 /var/piler
chmod 755 /var/piler/www
find /var/piler/www -type d -exec chmod 755 {} \;
find /var/piler/www -type f -exec chmod 644 {} \;
msg_ok "Configured Piler Web GUI"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/piler
server {
  listen 80 default_server;
    server_name _;
    root /var/piler/www;
    index index.php;

    access_log /var/log/nginx/piler-access.log;
    error_log /var/log/nginx/piler-error.log;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.3-fpm-piler.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(jpg|jpeg|gif|css|png|js|ico|html|woff|woff2)$ {
        access_log off;
        expires max;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/piler /etc/nginx/sites-enabled/piler
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/conf.d/default.conf
$STD nginx -t
$STD systemctl enable --now nginx
msg_ok "Configured Nginx"

msg_info "Setting Up Cron Jobs"
cat <<EOF >/etc/cron.d/piler
30 6 * * * piler /usr/local/libexec/piler/indexer.delta.sh
30 7 * * * piler /usr/local/libexec/piler/indexer.main.sh
*/15 * * * * piler /usr/local/bin/pilerstat
30 2 * * * piler /usr/local/bin/pilerpurge
3 * * * * piler /usr/local/bin/pilerconf
EOF
msg_ok "Set Up Cron Jobs"

motd_ssh
customize
cleanup_lxc
