#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/opf/openproject

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  sudo \
  curl \
  mc \
  lsb-release \
  ca-certificates \
  wget \
  acl \
  fping \
  graphviz \
  imagemagick \
  mariadb-client \
  mariadb-server \
  mtr-tiny \
  nginx-full \
  nmap \
  php8.2-{cli,fpm,gd,gmp,mbstring,mysql,snmp,xml,zip} \
  python3-{dotenv,pymysql,redis,setuptools,systemd,pip} \
  rrdtool \
  snmp \
  snmpd \
  unzip \
  whois
msg_ok "Installed Dependencies"

msg_info "Add User"
$STD useradd librenms -d /opt/librenms -M -r -s "$(which bash)"
msg_ok "Add User"

msg_info "Setup Librenms"
tmp_file=$(mktemp)
RELEASE=$(curl -s https://api.github.com/repos/librenms/librenms/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q https://github.com/librenms/librenms/archive/refs/tags/${RELEASE}.tar.gz -O $tmp_file
tar -xzf $tmp_file -C /opt
chown -R librenms:librenms /opt/librenms
chmod 771 /opt/librenms
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
msg_ok "Setup Librenms"

msg_info "Setup Composer"
cd /opt
wget -q https://getcomposer.org/composer-stable.phar
mv composer-stable.phar /usr/bin/composer
chmod +x /usr/bin/composer
msg_ok "Setup Composer"

msg_info "Setup PHP"
sed -i 's/;date.timezone =/date.timezone = UTC/' /etc/php/8.2/cli/php.ini
sed -i 's/;date.timezone =/date.timezone = UTC/' /etc/php/8.2/fpm/php.ini
msg_ok "Setup PHP"

msg_info "Setup MariaDB"
cat >/etc/mysql/mariadb.conf.d/50-server.cnf <<'EOF'
[mysqld]
innodb_file_per_table=1
lower_case_table_names=0
EOF

systemctl enable -q --now mariadb
msg_ok "Setup MariaDB"

msg_info "Configuring Database"
DB_NAME=librenms
DB_USER=librenms
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
mariadb -u root -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mariadb -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

{
  echo "LibreNMS-Credentials"
  echo "LibreNMS Database User: $DB_USER"
  echo "LibreNMS Database Password: $DB_PASS"
  echo "LibreNMS Database Name: $DB_NAME"
} >>~/librenms.creds
msg_ok "Configured Database"

msg_info "Configure PHP-FPM"
cp /etc/php/8.2/fpm/pool.d/www.conf /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/\[www\]/\[librenms\]/g" /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/user = www-data/user = librenms/g" /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/group = www-data/group = librenms/g" /etc/php/8.2/fpm/pool.d/librenms.conf
sed -i "s/listen = \/run\/php\/php8.2-fpm.sock/listen = \/run\/php-fpm-librenms.sock/g" /etc/php/8.2/fpm/pool.d/librenms.conf

msg_ok "Configured PHP-FPM"

msg_info "Configure Nginx"
cat >/etc/nginx/sites-available/librenms <<'EOF'
server {
 listen      80;
 server_name $(hostname -I | awk '{print $1}');
 root        /opt/librenms/html;
 index       index.php;

 charset utf-8;
 gzip on;
 gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;
 location / {
  try_files $uri $uri/ /index.php?$query_string;
 }
 location ~ [^/]\.php(/|$) {
  fastcgi_pass unix:/run/php-fpm-librenms.sock;
  fastcgi_split_path_info ^(.+\.php)(/.+)$;
  include fastcgi.conf;
 }
 location ~ /\.(?!well-known).* {
  deny all;
 }
}
EOF
rm /etc/nginx/sites-enabled/default
systemctl reload nginx
systemctl restart php8.2-fpm
msg_ok "Configured Nginx"

msg_info "Configure Services"
ln -s /opt/librenms/lnms /usr/bin/lnms
cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/

cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf

RANDOM_STRING=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
sed -i "s/RANDOMSTRINGHERE/$RANDOM_STRING/g" /etc/snmp/snmpd.conf
echo "SNMP Community String: $RANDOM_STRING" >>~/librenms.creds
curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro
systemctl enable -q --now snmpd

cp /opt/librenms/dist/librenms.cron /etc/cron.d/librenms
cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/

systemctl enable librenms-scheduler.timer
systemctl start librenms-scheduler.timer
cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms
msg_ok "Configured Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
