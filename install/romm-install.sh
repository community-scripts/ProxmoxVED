#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: DevelopmentCats
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://romm.app
# Updated: 03/10/2025

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
  acl \
  build-essential \
  libssl-dev \
  libffi-dev \
  python3-dev \
  python3-pip \
  python3-venv \
  libmariadb3 \
  libmariadb-dev \
  libpq-dev \
  redis-tools \
  p7zip \
  tzdata \
  jq
msg_ok "Installed core dependencies"

PYTHON_VERSION="3.12" setup_uv
NODE_VERSION="22" NODE_MODULE="serve" setup_nodejs
setup_mariadb

msg_info "Configuring Database"
DB_NAME=romm
DB_USER=romm
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mariadb -u root -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$STD mariadb -u root -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
$STD mariadb -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "RomM-Credentials"
  echo "RomM Database User: $DB_USER"
  echo "RomM Database Password: $DB_PASS"
  echo "RomM Database Name: $DB_NAME"
} >~/romm.creds
chmod 600 ~/romm.creds
msg_ok "Configured Database"

msg_info "Creating romm user and directories"
id -u romm &>/dev/null || useradd -r -m -d /var/lib/romm -s /bin/bash romm
mkdir -p /opt/romm \
  /var/lib/romm/config \
  /var/lib/romm/resources \
  /var/lib/romm/assets/{saves,states,screenshots} \
  /var/lib/romm/library/roms/{gba,gbc,ps} \
  /var/lib/romm/library/bios/{gba,ps}
chown -R romm:romm /opt/romm /var/lib/romm
msg_ok "Created romm user and directories"

msg_info "Configuring Database"
DB_NAME=romm
DB_USER=romm
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mariadb -u root -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
$STD mariadb -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "RomM-Credentials"
  echo "RomM Database User: $DB_USER"
  echo "RomM Database Password: $DB_PASS"
  echo "RomM Database Name: $DB_NAME"
} >~/romm.creds
msg_ok "Configured Database"

fetch_and_deploy_gh_release "romm" "rommapp/romm"

msg_info "Creating environment file"
sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
systemctl restart redis-server
systemctl enable -q --now redis-server
AUTH_SECRET_KEY=$(openssl rand -hex 32)

cat >/opt/romm/.env <<EOF
ROMM_BASE_PATH=/var/lib/romm
WEB_CONCURRENCY=4

DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWD=$DB_PASS

REDIS_HOST=127.0.0.1
REDIS_PORT=6379

ROMM_AUTH_SECRET_KEY=$AUTH_SECRET_KEY
DISABLE_DOWNLOAD_ENDPOINT_AUTH=false
DISABLE_CSRF_PROTECTION=false

ENABLE_RESCAN_ON_FILESYSTEM_CHANGE=true
RESCAN_ON_FILESYSTEM_CHANGE_DELAY=5

ENABLE_SCHEDULED_RESCAN=true
SCHEDULED_RESCAN_CRON=0 3 * * *
ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB=true
SCHEDULED_UPDATE_SWITCH_TITLEDB_CRON=0 4 * * *

LOGLEVEL=INFO
EOF

chown romm:romm /opt/romm/.env
chmod 600 /opt/romm/.env
msg_ok "Created environment file"

msg_info "Installing backend"
cd /opt/romm
uv pip install --all-extras .
cd /opt/romm/backend
uv run alembic upgrade head
chown -R romm:romm /opt/romm
msg_ok "Installed backend"

msg_info "Installing frontend"
cd /opt/romm/frontend
npm install
npm run build
ln -sfn /var/lib/romm/resources /opt/romm/frontend/assets/romm/resources
ln -sfn /var/lib/romm/assets /opt/romm/frontend/assets/romm/assets
chown -R romm:romm /opt/romm
msg_ok "Installed frontend"

msg_info "Creating services"

cat >/etc/systemd/system/romm-backend.service <<EOF
[Unit]
Description=RomM Backend
After=network.target mariadb.service redis-server.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
User=romm
WorkingDirectory=/opt/romm/backend
Environment="PYTHONPATH=/opt/romm"
ExecStart=/opt/romm/.venv/bin/uv run gunicorn main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:5000
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/romm-frontend.service <<EOF
[Unit]
Description=RomM Frontend
After=network.target

[Service]
Type=simple
User=romm
WorkingDirectory=/opt/romm/frontend
ExecStart=$(which serve) -s dist -l 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/romm-worker.service <<EOF
[Unit]
Description=RomM Worker
After=network.target mariadb.service redis-server.service romm-backend.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
User=romm
WorkingDirectory=/opt/romm/backend
Environment="PYTHONPATH=/opt/romm"
ExecStart=/opt/romm/.venv/bin/uv run python3 worker.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/romm-scheduler.service <<EOF
[Unit]
Description=RomM Scheduler
After=network.target mariadb.service redis-server.service romm-backend.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
User=romm
WorkingDirectory=/opt/romm/backend
Environment="PYTHONPATH=/opt/romm"
ExecStart=/opt/romm/.venv/bin/uv run python3 scheduler.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now romm-backend romm-frontend romm-worker romm-scheduler
msg_ok "Created services"

# Install serve globally
su - ${ROMM_USER} -c "npm install -g serve"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned up"
