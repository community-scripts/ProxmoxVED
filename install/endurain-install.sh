#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: johanngrobe
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/joaovitoriasilva/endurain

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y default-libmysqlclient-dev build-essential pkg-config
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.13" setup_uv
NODE_VERSION="22" NODE_MODULE="npm@latest" setup_nodejs
PG_VERSION="17" PG_MODULES="postgis,contrib" setup_postgresql

fetch_and_deploy_gh_release "endurain" "joaovitoriasilva/endurain" "tarball" "latest" "/opt/endurain"

msg_info "Setting up Endurain"
DB_NAME=enduraindb
DB_USER=endurain
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
DB_PORT=5432
DB_HOST=localhost

$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"

cd /opt/endurain
rm -rf \
  /opt/endurain/{docs,example.env,screenshot_01.png} \
  /opt/endurain/docker* \
  /opt/endurain/*.yml
mkdir -p /opt/endurain_data/{data,logs}
SECRET_KEY=$(openssl rand -hex 32)
FERNET_KEY=$(openssl rand -base64 32)
IP=$(hostname -I | awk '{print $1}')
ENDURAIN_HOST=http://${IP}:8080
cat <<EOF > /opt/endurain/.env

DB_PASSWORD=${DB_PASS}

SECRET_KEY=${SECRET_KEY}
FERNET_KEY=${FERNET_KEY}

TZ=Europe/Berlin
ENDURAIN_HOST=${ENDURAIN_HOST}
BEHIND_PROXY=false

POSTGRES_DB=${DB_NAME}
POSTGRES_USER=${DB_USER}
PGDATA=/var/lib/postgresql/${DB_NAME}

DB_DATABASE=${DB_NAME}
DB_USER=${DB_USER}
DB_PORT=${DB_PORT}
DB_HOST=${DB_HOST}

DATABASE_URL=postgresql+psycopg://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}

BACKEND_DIR="/opt/endurain/backend/app"
FRONTEND_DIR="/opt/endurain/frontend/app/dist"
DATA_DIR="/opt/endurain_data/data"
LOGS_DIR="/opt/endurain_data/logs"

#SMTP_HOST=smtp.protonmail.ch
#SMTP_PORT=587
#SMTP_USERNAME=your-email@example.com
#SMTP_PASSWORD=your-app-password
#SMTP_SECURE=true
#SMTP_SECURE_TYPE=starttls
EOF
msg_ok "Setup Endurain"

msg_info "Building Frontend"
cd /opt/endurain/frontend/app || exit
$STD npm ci --prefer-offline
$STD npm run build
cat <<EOF > /opt/endurain/frontend/app/dist/env.js
window.env = {
  ENDURAIN_HOST: "${ENDURAIN_HOST}"
}
EOF
msg_ok "Build Frontend"

msg_info "Setting up Backend"
cd /opt/endurain/backend || exit
$STD uv tool install poetry
$STD uv tool update-shell
$STD export PATH="/root/.local/bin:$PATH"
$STD poetry self add poetry-plugin-export
$STD poetry export -f requirements.txt --output requirements.txt --without-hashes
$STD uv venv
$STD uv pip install -r requirements.txt
msg_ok "Setup Backend"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/endurain.service
[Unit]
Description=Endurain FastAPI Backend
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/endurain/backend/app
EnvironmentFile=/opt/endurain/.env
ExecStart=/opt/endurain/backend/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now endurain
msg_ok "Service Created & Started"

motd_ssh
customize
cleanup_lxc
