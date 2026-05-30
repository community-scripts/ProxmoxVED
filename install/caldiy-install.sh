#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: masterde
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  openssl \
  ca-certificates \
  build-essential \
  python3
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="caldiy" PG_DB_USER="caldiy" setup_postgresql_db

msg_info "Cloning ${APPLICATION} Repository"
$STD git clone -c core.symlinks=true https://github.com/calcom/cal.diy.git /opt/caldiy
msg_ok "Cloned Repository"

msg_info "Configuring Environment"
cd /opt/caldiy || exit
cp .env.example .env
[[ -f .env.appStore.example ]] && cp .env.appStore.example .env.appStore

NEXTAUTH_SECRET="$(openssl rand -base64 32)"
ENCRYPTION_KEY="$(openssl rand -base64 24)"
DB_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}"

# set_env <KEY> <VALUE>: replace the line in-place if the key exists, otherwise append it
set_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" .env
  else
    echo "${key}=\"${val}\"" >>.env
  fi
}

set_env "DATABASE_URL" "${DB_URL}"
set_env "DATABASE_DIRECT_URL" "${DB_URL}"
set_env "NEXTAUTH_SECRET" "${NEXTAUTH_SECRET}"
set_env "CALENDSO_ENCRYPTION_KEY" "${ENCRYPTION_KEY}"
set_env "NEXTAUTH_URL" "http://${LOCAL_IP}:3000"
set_env "NEXT_PUBLIC_WEBAPP_URL" "http://${LOCAL_IP}:3000"
set_env "NEXT_PUBLIC_WEBSITE_URL" "http://${LOCAL_IP}:3000"

{
  echo "${APPLICATION} Credentials"
  echo "Web URL: http://${LOCAL_IP}:3000"
  echo "Database Name: ${PG_DB_NAME}"
  echo "Database User: ${PG_DB_USER}"
  echo "Database Password: ${PG_DB_PASS}"
  echo "NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}"
  echo "CALENDSO_ENCRYPTION_KEY: ${ENCRYPTION_KEY}"
} >>~/caldiy.creds
msg_ok "Configured Environment"

msg_info "Installing Packages & Building ${APPLICATION} (Patience, this can take 15+ minutes)"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export NODE_OPTIONS="--max-old-space-size=7168"
$STD corepack enable
$STD yarn install
$STD yarn workspace @calcom/prisma db-deploy
$STD yarn build
msg_ok "Built ${APPLICATION}"

msg_info "Creating Service"
cat <<SERVICE >/etc/systemd/system/caldiy.service
[Unit]
Description=Cal.diy Service
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/caldiy
EnvironmentFile=/opt/caldiy/.env
Environment=NODE_OPTIONS=--max-old-space-size=4096
ExecStart=/usr/bin/yarn start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable -q --now caldiy
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
