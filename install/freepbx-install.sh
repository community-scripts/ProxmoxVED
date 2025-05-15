#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Arian Nasr (arian-nasr)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.freepbx.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  git \
  libnewt-dev \
  libssl-dev \
  libncurses5-dev \
  subversion \
  libsqlite3-dev \
  libjansson-dev \
  libxml2-dev \
  uuid-dev \
  default-libmysqlclient-dev \
  htop \
  sngrep \
  lame \
  ffmpeg \
  mpg123 \
  vim \
  expect \
  openssh-server \
  apache2 \
  mariadb-server \
  mariadb-client \
  bison \
  flex \
  php8.2 \
  php8.2-{curl,cli,common,mysql,gd,mbstring,intl,xml} \
  php-pear \
  sox \
  sqlite3 \
  pkg-config \
  automake \
  libtool \
  autoconf \
  unixodbc-dev \
  uuid \
  libasound2-dev \
  libogg-dev \
  libvorbis-dev \
  libicu-dev \
  libcurl4-openssl-dev \
  odbc-mariadb \
  libical-dev \
  libneon27-dev \
  libsrtp2-dev \
  libspandsp-dev \
  subversion \
  libtool-bin \
  python-dev-is-python3 \
  unixodbc \
  software-properties-common \
  nodejs \
  npm \
  ipset \
  iptables \
  fail2ban \
  php-soap
msg_ok "Installed Dependencies"

msg_info "Installing Asterisk (Patience)"
cd /usr/src
curl -fsSL http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-21-current.tar.gz
tar xf asterisk-21-current.tar.gz
cd asterisk-21.*
$STD contrib/scripts/get_mp3_source.sh
$STD contrib/scripts/install_prereq install
$STD ./configure --libdir=/usr/lib64 --with-pjproject-bundled --with-jansson-bundled
$STD make
$STD make install
$STD make samples
$STD make config
ldconfig
msg_ok "Installed Asterisk"

msg_info "Setup Asterisk"
groupadd asterisk
useradd -r -d /var/lib/asterisk -g asterisk asterisk
usermod -aG audio,dialout asterisk
chown -R asterisk:asterisk /etc/asterisk
chown -R asterisk:asterisk /var/{lib,log,spool}/asterisk
chown -R asterisk:asterisk /usr/lib64/asterisk
sed -i 's|#AST_USER|AST_USER|' /etc/default/asterisk
sed -i 's|#AST_GROUP|AST_GROUP|' /etc/default/asterisk
sed -i 's|;runuser|runuser|' /etc/asterisk/asterisk.conf
sed -i 's|;rungroup|rungroup|' /etc/asterisk/asterisk.conf
echo "/usr/lib64" >>/etc/ld.so.conf.d/x86_64-linux-gnu.conf
ldconfig
msg_ok "Done Setup Asterisk"

msg_info "Setup Apache"
sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/8.2/apache2/php.ini
sed -i 's/\(^memory_limit = \).*/\1256M/' /etc/php/8.2/apache2/php.ini
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
$STD a2enmod rewrite
systemctl restart apache2
rm /var/www/html/index.html
msg_ok "Done Setup Apache"

# Configure ODBC
cat <<EOF >/etc/odbcinst.ini
[MySQL]
Description = ODBC for MySQL (MariaDB)
Driver = /usr/lib/x86_64-linux-gnu/odbc/libmaodbc.so
FileUsage = 1
EOF

cat <<EOF >/etc/odbc.ini
[MySQL-asteriskcdrdb]
Description = MySQL connection to 'asteriskcdrdb' database
Driver = MySQL
Server = localhost
Database = asteriskcdrdb
Port = 3306
Socket = /var/run/mysqld/mysqld.sock
Option = 3
EOF

msg_info "Installing FreePBX"
cd /usr/local/src
curl -fsSL http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest-EDGE.tgz -o freepbx-17.0-latest-EDGE.tgz
tar zxf freepbx-17.0-latest-EDGE.tgz
cd /usr/local/src/freepbx/
$STD ./start_asterisk start
# Even though the php code completes successfully, it is returning non-zero exit code, so in the next line we return true, needed for successful installation
./install -n &>/dev/null || true
$STD fwconsole ma installall
$STD fwconsole reload
$STD fwconsole restart
msg_ok "Installed FreePBX"

msg_info "Setup FreePBX Service"
cat <<EOF >/etc/systemd/system/freepbx.service
[Unit]
Description=FreePBX VoIP Server
After=mariadb.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/fwconsole start -q
ExecStop=/usr/sbin/fwconsole stop -q
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now freepbx
msg_ok "Done Setup FreePBX Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
