#!/usr/bin/env bash

# Copyright (c) 2025 Community Scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/maxdorninger/MediaManager

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y yq
msg_ok "Installed dependencies"

NODE_VERSION="24" setup_nodejs
setup_uv
PG_VERSION="17" setup_postgresql

msg_info "Setting up PostgreSQL"
DB_NAME="mm_db"
DB_USER="mm_user"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
{
  echo "MediaManager Credentials"
  echo "MediaManager Database User: $DB_USER"
  echo "MediaManager Database Password: $DB_PASS"
  echo "MediaManager Database Name: $DB_NAME"
} >>~/mediamanager.creds
msg_ok "Set up PostgreSQL"

fetch_and_deploy_gh_release "MediaManager" "maxdorninger/MediaManager" "tarball" "latest" "/opt/mediamanager"
msg_info "Configuring MediaManager"
export CONFIG_DIR="/opt/mm_data/"
export FRONTEND_FILES_DIR="/opt/mm_data/web/build"
export BASE_PATH=""
export PUBLIC_VERSION=""
export PUBLIC_API_URL="${BASE_PATH}/api/v1"
export BASE_PATH="${BASE_PATH}/web"
cd /opt/mediamanager/web
$STD npm ci
$STD npm run build
mkdir -p "$CONFIG_DIR"/web
cp -r build "$FRONTEND_FILES_DIR"
cp -r media_manager "$CONFIG_DIR"
cp -r alembic* "$CONFIG_DIR"

export BASE_PATH=""
export VIRTUAL_ENV="/opt/mm_data/venv"
cd /opt/mediamanager
$STD /usr/local/bin/uv venv "$VIRTUAL_ENV"
$STD /usr/local/bin/uv sync --locked --active
msg_ok "Configured MediaManager"

read -r -p "Enter the email address of your first admin user: " admin_email
if [[ "$admin_email" ]]; then
  EMAIL="$admin_email"
fi

msg_info "Creating config and start script"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
SECRET="$(openssl rand -hex 32)"
sed -e "s/localhost:8/$LOCAL_IP:8/g" \
  -e "s|/data/|$CONFIG_DIR|g" \
  -e 's/"db"/"localhost"/' \
  -e "s/user = \"MediaManager\"/user = \"$DB_USER\"/" \
  -e "s/password = \"MediaManager\"/password = \"$DB_PASS\"/" \
  -e "s/dbname = \"MediaManager\"/dbname = \"$DB_NAME\"/" \
  -e "/^token_secret/s/=.*/= \"$SECRET\"/" \
  -e "s/admin@example.com/$EMAIL/" \
  -e '/^admin_emails/s/, .*/]/' \
  /opt/mediamanager/config.example.toml >/opt/mm_data/config.toml

mkdir -p "$CONFIG_DIR"/{images,tv,movies,torrents}

cat <<EOF >/opt/mm_data/start.sh
#!/usr/bin/env bash

export CONFIG_DIR="$CONFIG_DIR"
export FRONTEND_FILES_DIR="$FRONTEND_FILES_DIR"

cd /opt/mediamanager
/usr/local/bin/uv run alembic upgrade head
/usr/local/bin/uv run fastapi run ./media_manager/main.py --port 8000
EOF
chmod +x /opt/mm_data/start.sh
msg_ok "Created config and start script"

msg_info "Creating service"
cat <<EOF >/etc/systemd/system/mediamanager.service
[Unit]
Description=MediaManager Backend Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/mm_data
ExecStart=/usr/bin/bash start.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mediamanager
msg_ok "Created service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
