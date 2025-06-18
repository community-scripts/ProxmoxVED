#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/gitroomhq/postiz-app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
  build-essential \
  python3-pip \
  supervisor \
  debian-keyring \
  debian-archive-keyring \
  apt-transport-https \
  redis
msg_ok "Installed dependencies"

NODE_VERSION="20" setup_nodejs
PG_VERSION="17" setup_postgresql

msg_info "Setting up PostgreSQL Database"
DB_NAME=postiz
DB_USER=postiz
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "Postiz DB Credentials"
  echo "Postiz Database User: $DB_USER"
  echo "Postiz Database Password: $DB_PASS"
  echo "Postiz Database Name: $DB_NAME"
} >>~/postiz.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Setting up Caddy"
curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" >/etc/apt/sources.list.d/caddy-stable.list
$STD apt-get update
$STD apt-get install caddy
msg_ok "Set up Caddy"

fetch_and_deploy_gh_release "gitroomhq/postiz-app"

msg_info "Configuring Postiz"
LOCAL_IP=$(hostname -I | awk '{print $1}')
JWT_SECRET=$(openssl rand -base64 64 | tr '+/' '-_' | tr -d '=')
cd /opt/postiz
mkdir -p /etc/supervisor.d
$STD npm --no-update-notifier --no-fund --global install pnpm@10.6.1 pm2
cp var/docker/supervisord.conf /etc/supervisord.conf
cp var/docker/Caddyfile ./Caddyfile
cp var/docker/entrypoint.sh ./entrypoint.sh
cp var/docker/supervisord/caddy.conf /etc/supervisor.d/caddy.conf
sed -i "s#/app/Caddyfile#/opt/postiz/Caddyfile#g" /etc/supervisor.d/caddy.conf
sed -i "s#/app/Caddyfile#/opt/postiz/Caddyfile#g" /opt/postiz/entrypoint.sh
sed -i "s#directory=/app#directory=/opt/postiz#g" /etc/supervisor.d/caddy.conf
export NODE_OPTIONS="--max-old-space-size=2560"
$STD pnpm install
$STD pnpm run build
chmod +x entrypoint.sh

cat <<EOF >.env
NOT_SECURED="true"
IS_GENERAL="true"
DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
REDIS_URL="redis://localhost:6379"
JWT_SECRET="$JWT_SECRET"
FRONTEND_URL="http://$LOCAL_IP:4200"
NEXT_PUBLIC_BACKEND_URL="http://$LOCAL_IP:3000"
BACKEND_INTERNAL_URL="http://$LOCAL_IP:3000"
EOF
msg_ok "Configured Postiz"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/postiz.service
[Unit]
Description=Postiz Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/postiz
EnvironmentFile=/opt/postiz/.env
ExecStart=/usr/bin/pnpm run pm2-run
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now postiz
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
