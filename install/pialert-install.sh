#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/leiweibau/Pi.Alert/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get -y install \
  apt-utils \
  avahi-utils \
  lighttpd \
  sqlite3 \
  mmdb-bin \
  arp-scan \
  dnsutils \
  net-tools \
  nbtscan \
  libwww-perl \
  nmap \
  aria2 \
  wakeonlan \
  fping \
  zip \
  libtext-csv-perl \
  python3-requests \
  python3-tz \
  python3-tzlocal \
  python3-aiohttp \
  python3-cryptography

msg_ok "Installed Dependencies"

PHP_VERSION="8.3" PHP_MODULE="sqlite3,xml,cgi" PHP_FPM="YES" setup_php
PYTHON_VERSION="3.13" setup_uv
fetch_and_deploy_gh_release "pialert" "leiweibau/Pi.Alert"

msg_info "Installing Pi.Alert"
$STD lighttpd-enable-mod fastcgi-php
service lighttpd force-reload
$STD uv --system pip install mac-vendor-lookup fritzconnection cryptography pyunifi openwrt-luci-rpc asusrouter paho-mqtt
rm -rf /var/lib/ieee-data /var/www/html/index.html
sed -i -e 's#^sudo cp -n /usr/share/ieee-data/.* /var/lib/ieee-data/#\# &#' -e '/^sudo mkdir -p 2_backup$/s/^/# /' -e '/^sudo cp \*.txt 2_backup$/s/^/# /' -e '/^sudo cp \*.csv 2_backup$/s/^/# /' /opt/pialert/back/update_vendors.sh
mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.html.old
ln -s /usr/share/ieee-data/ /var/lib/
ln -s /opt/pialert/install/index.html /var/www/html/index.html
ln -s /opt/pialert/front /var/www/html/pialert
chmod go+x /opt/pialert /opt/pialert/back/shoutrrr/x86/shoutrrr
chgrp -R www-data /opt/pialert/db /opt/pialert/front/reports /opt/pialert/config /opt/pialert/config/pialert.conf
chmod -R 775 /opt/pialert/db /opt/pialert/db/temp /opt/pialert/config /opt/pialert/front/reports
touch /opt/pialert/log/pialert.vendors.log /opt/pialert/log/pialert.IP.log /opt/pialert/log/pialert.1.log /opt/pialert/log/pialert.cleanup.log /opt/pialert/log/pialert.webservices.log
src_dir="/opt/pialert/log"
dest_dir="/opt/pialert/front/php/server"
for file in pialert.vendors.log pialert.IP.log pialert.1.log pialert.cleanup.log pialert.webservices.log; do
  ln -s "$src_dir/$file" "$dest_dir/$file"
done
sed -i 's#PIALERT_PATH\s*=\s*'\''/home/pi/pialert'\''#PIALERT_PATH           = '\''/opt/pialert'\''#' /opt/pialert/config/pialert.conf
sed -i 's/$HOME/\/opt/g' /opt/pialert/install/pialert.cron
crontab /opt/pialert/install/pialert.cron
echo "python3 /opt/pialert/back/pialert.py 1" >/usr/bin/scan
chmod +x /usr/bin/scan
echo "/opt/pialert/back/pialert-cli set_permissions --lxc" >/usr/bin/permissions
chmod +x /usr/bin/permissions
echo "/opt/pialert/back/pialert-cli set_sudoers --lxc" >/usr/bin/sudoers
chmod +x /usr/bin/sudoers
msg_ok "Installed Pi.Alert"

msg_info "Start Pi.Alert Scan (Patience)"
$STD python3 /opt/pialert/back/pialert.py update_vendors
$STD python3 /opt/pialert/back/pialert.py internet_IP
$STD python3 /opt/pialert/back/pialert.py 1
msg_ok "Finished Pi.Alert Scan"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
