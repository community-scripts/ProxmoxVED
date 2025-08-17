#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: CillyCil
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/redimp/otterwiki

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  build-essential \
  python3-dev \
  python3-venv
msg_ok "Installed Dependencies"

# # Template: MySQL Database
# msg_info "Setting up Database"
# DB_NAME=[DB_NAME]
# DB_USER=[DB_USER]
# DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
# $STD mysql -u root -e "CREATE DATABASE $DB_NAME;"
# $STD mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password AS PASSWORD('$DB_PASS');"
# $STD mysql -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
# {
#   echo "${APPLICATION} Credentials"
#   echo "Database User: $DB_USER"
#   echo "Database Password: $DB_PASS"
#   echo "Database Name: $DB_NAME"
# } >>~/"$APP_NAME".creds
# msg_ok "Set up Database"

# Setup App
msg_info "Setup ${APPLICATION}"
RELEASE=$(curl -fsSL https://api.github.com/repos/redimp/otterwiki/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL -o "${RELEASE}.zip" "https://github.com/redimp/otterwiki/archive/refs/tags/${RELEASE}.zip"
unzip -q "${RELEASE}.zip"
mv "otterwiki-${RELEASE:1}/" "/opt/otterwiki"
cd /opt/otterwiki || exit
mkdir -p app-data/repository
# initialize the empty repository
git init -b main app-data/repository
echo "REPOSITORY='${PWD}/app-data/repository'" >> settings.cfg
echo "SQLALCHEMY_DATABASE_URI='sqlite:///${PWD}/app-data/db.sqlite'" >> settings.cfg
echo "SECRET_KEY='$(python3 -c 'import secrets; print(secrets.token_hex())')'" >> settings.cfg
python3 -m venv venv
./venv/bin/pip install -U pip uwsgi
./venv/bin/pip install .
echo "${RELEASE}" >/opt/otterwiki_version.txt
msg_ok "Setup ${APPLICATION}"

# Creating Service (if needed)
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/otterwiki.service
[Unit]
Description=uWSGI server for An Otter Wiki

[Service]
User=root
Environment=OTTERWIKI_SETTINGS=/opt/otterwiki/settings.cfg
ExecStart=/opt/OtterWiki/venv/bin/uwsgi --http 127.0.0.1:8080 --enable-threads --die-on-term -w otterwiki.server:app
SyslogIdentifier=otterwiki

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now otterwiki
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f "${RELEASE}".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
