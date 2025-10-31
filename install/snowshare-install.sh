#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: TuroYT
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  make \
  gnupg \
  ca-certificates

msg_ok "Installed Dependencies"

setup_nodejs

msg_info "Setting up PostgreSQL Database"
DB_NAME=snowshare
DB_USER=snowshare
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
setup_postgresql
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
echo "" >>~/snowshare.creds
echo -e "Database Username: $DB_USER" >>~/snowshare.creds
echo -e "Database Password: $DB_PASS" >>~/snowshare.creds
echo -e "Database Name: $DB_NAME" >>~/snowshare.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Installing SnowShare (Patience)"

APP="snowshare"

cd /opt

fetch_and_deploy_gh_release "snowshare" "TuroYT/snowshare"

cd /opt/snowshare


$STD npm ci


echo "${RELEASE}" >/opt/${APP}_version.txt

cat <<EOF >/opt/snowshare/.env
DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
NEXTAUTH_URL="http://localhost:3000"
NEXTAUTH_SECRET="$(openssl rand -base64 32)"
ALLOW_SIGNUP=true
NODE_ENV=production
EOF

cd /opt/snowshare
$STD npx prisma generate
$STD npx prisma migrate deploy


cd /opt/snowshare
$STD npm run build


cat <<EOF >/etc/systemd/system/snowshare.service
[Unit]
Description=SnowShare - Modern File Sharing Platform
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/snowshare
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now snowshare.service
msg_ok "Installed SnowShare v${RELEASE}"

msg_info "Setting up Cleanup Cron Job"
cat <<EOF >/etc/cron.d/snowshare-cleanup
0 2 * * * root cd /opt/snowshare && /usr/bin/npm run cleanup:expired >> /var/log/snowshare-cleanup.log 2>&1
EOF
msg_ok "Set up Cleanup Cron Job"

motd_ssh
customize

msg_info "Cleaning up"

$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean

msg_ok "Cleaned"
