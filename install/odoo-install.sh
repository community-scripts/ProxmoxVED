#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE
# Source: https://github.com/odoo/odoo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  build-essential \
  make
msg_ok "Installed Dependencies"

PG_VERSION="16" install_postgresql

msg_info "Setup PostgreSQL Database"
DB_NAME="odoo"
DB_USER="odoo_usr"
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
$STD sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;"
$STD sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
{
  echo "Odoo-Credentials"
  echo -e "Odoo Database User: $DB_USER"
  echo -e "Odoo Database Password: $DB_PASS"
  echo -e "Odoo Database Name: $DB_NAME"
} >>~/odoo.creds
msg_ok "Setup PostgreSQL"

msg_info "Get latest Odoo Release"
RELEASE=$(curl -fsSL https://nightly.odoo.com/ | grep -oE 'href="[0-9]+\.[0-9]+/nightly"' | head -n1 | cut -d'"' -f2 | cut -d/ -f1)
curl -fsSL https://nightly.odoo.com/$RELEASE/nightly/deb/odoo_$RELEASE.latest_all.deb -o /opt/odoo.deb
cd /opt
apt install ./odoo.deb
msg_ok "Installed Odoo $RELEASE"

msg_info "Configuring Odoo"
sed -i \
  -e "s|^;*db_host *=.*|db_host = localhost|" \
  -e "s|^;*db_port *=.*|db_port = 5432|" \
  -e "s|^;*db_user *=.*|db_user = $DB_USER|" \
  -e "s|^;*db_password *=.*|db_password = $DB_PASS|" \
  /etc/odoo/odoo.conf
msg_ok "Configured Odoo"

msg_info "Restarting Odoo"
systemctl restart odoo
msg_ok "Restarted Odoo"
# setup_uv

# msg_info "Creating Python Virtual Environment"
# $STD uv venv /opt/odoo/.venv
# $STD source /opt/odoo/.venv/bin/activate
# $STD uv pip install --upgrade pip wheel
# $STD uv pip install -r /opt/odoo/odoo/requirements.txt
# msg_ok "Created and populated Python venv"

# msg_info "Creating Configuration File"
# cat <<EOF >/opt/odoo/odoo.conf
# [options]
# addons_path = /opt/odoo/odoo/addons
# admin_passwd = admin
# db_host = localhost
# db_port = 5432
# db_user = odoo
# db_password = odoo
# logfile = /var/log/odoo.log
# EOF
# chown odoo:odoo /opt/odoo/odoo.conf
# chmod 640 /opt/odoo/odoo.conf
# msg_ok "Created Configuration File"

# msg_info "Creating Systemd Service"
# cat <<EOF >/etc/systemd/system/odoo.service
# [Unit]
# Description=Odoo ERP
# After=network.target postgresql.service

# [Service]
# Type=simple
# User=odoo
# Group=odoo
# Environment="PATH=/opt/odoo/.venv/bin:/usr/local/bin:/usr/bin"
# ExecStart=/opt/odoo/.venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /opt/odoo/odoo.conf
# Restart=on-failure

# [Install]
# WantedBy=multi-user.target
# EOF
# systemctl enable -q --now odoo
# msg_ok "Enabled and Started Odoo Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
