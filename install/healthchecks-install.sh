#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  gcc \
  libpq-dev \
  libcurl4-openssl-dev \
  libssl-dev
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y \
  python3 python3-dev python3-pip
$STD pip install --upgrade pip
msg_ok "Setup Python3"

setup_uv
PG_VERSION=16 install_postgresql

msg_info "Setup Database"
DB_NAME=healthchecks_db
DB_USER=hc_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
SECRET_KEY="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)"

$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "healthchecks-Credentials"
  echo "healthchecks Database User: $DB_USER"
  echo "healthchecks Database Password: $DB_PASS"
  echo "healthchecks Database Name: $DB_NAME"
} >>~/healthchecks.creds
msg_ok "Set up Database"

msg_info "Setup healthchecks"
cd /opt
RELEASE=$(curl -s https://api.github.com/repos/healthchecks/healthchecks/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
curl -fsSL "https://github.com/healthchecks/healthchecks/archive/refs/tags/v${RELEASE}.zip" -o v${RELEASE}.zip
unzip -q v${RELEASE}.zip
mv healthchecks-${RELEASE} /opt/healthchecks
cd /opt/healthchecks
$STD uv venv .venv
$STD source .venv/bin/activate
$STD uv pip install wheel
$STD uv pip install -r requirements.txt
cat <<EOF >/opt/healthchecks/.env
ALLOWED_HOSTS=localhost
DB=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}
DB_CONN_MAX_AGE=0
DB_SSLMODE=prefer
DB_TARGET_SESSION_ATTRS=read-write

DEFAULT_FROM_EMAIL=healthchecks@example.org
EMAIL_HOST=
EMAIL_HOST_PASSWORD=
EMAIL_HOST_USER=
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_USE_VERIFICATION=True

# Django & Healthchecks Konfiguration
SECRET_KEY=${SECRET_KEY}
DEBUG=False

SITE_ROOT=http://0.0.0.0:8000
SITE_NAME=Mychecks
SITE_ROOT=http://0.0.0.0:8000
EOF

ADMIN_EMAIL="admin@helper-scripts.local"
ADMIN_PASSWORD="$DB_PASS"

cat <<EOF | $STD .venv/bin/python3 manage.py shell
from django.contrib.auth import get_user_model
User = get_user_model()

if not User.objects.filter(email="${ADMIN_EMAIL}").exists():
    u = User.objects.create_superuser(
        username="${ADMIN_EMAIL}",
        email="${ADMIN_EMAIL}",
        password="${ADMIN_PASSWORD}"
    )
    u.is_active = True
    u.is_staff = True
    u.is_superuser = True
    u.save()
EOF

$STD python3 manage.py migrate
msg_ok "Installed healthchecks"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/healthchecks.service
[Unit]
Description=Healthchecks Service
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/healthchecks/
ExecStart=/opt/healthchecks/.venv/bin/python3 manage.py runserver 0.0.0.0:8000
Restart=always
EnvironmentFile=/opt/healthchecks/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now healthchecks
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/v${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
