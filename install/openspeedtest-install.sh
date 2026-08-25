#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Kaywinnett
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/openspeedtest/Speed-Test

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "http port: ${var_http_port}"
msg_info "https port: ${var_https_port}"

msg_info "Installing Depenencies"
$STD apt install -y \
    apache2
msg_ok "Installed Dependencies"

systemctl stop apache2

setup_nodejs

fetch_and_deploy_gh_release "openspeedtest" "kaywinnett/Speed-Test"

msg_info "Configuring Apache2"

cat <<EOF >/etc/apache2/sites-available/openspeedtest.conf
<VirtualHost *:${var_http_port}>
    DocumentRoot /opt/openspeedtest

    <Directory />
	Order allow,deny
	Allow from all
	Require all granted
    </Directory>
</virtualHost>
EOF

sed -i "s/Listen 80/Listen ${var_http_port}/" /etc/apache2/ports.conf
sed -i "s/Listen 443/Listen ${var_https_port}/" /etc/apache2/ports.conf

msg_ok "Configured Apache2"

$STD a2dissite 000-default.conf
$STD a2ensite openspeedtest.conf
systemctl restart apache2
msg_ok "Started Apache2"

motd_ssh
customize
cleanup_lxc
