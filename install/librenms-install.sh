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
cat > /etc/mysql/mariadb.conf.d/50-server.cnf << 'EOF'
[mysqld]
innodb_file_per_table=1
lower_case_table_names=0
EOF

systemctl enable -q --now mariadb



msg_ok "Setup MariaDB"


motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
