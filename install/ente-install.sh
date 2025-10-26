#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ente-io/ente

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    libsodium23 \
    libsodium-dev \
    pkg-config \
    caddy \
    gcc
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
setup_go
NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs
fetch_and_deploy_gh_release "ente" "ente-io/ente" "tarball" "latest" "/opt/ente"

msg_info "Setting up PostgreSQL"
DB_NAME="ente_db"
DB_USER="ente"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
{
    echo "Ente Credentials"
    echo "Database Name: $DB_NAME"
    echo "Database User: $DB_USER"
    echo "Database Password: $DB_PASS"
} >>~/ente.creds
msg_ok "Set up PostgreSQL"

# Download Ente cli
msg_info "Downloading Ente CLI"
$STD mkdir -p /opt/ente/cli/dist
fetch_and_deploy_gh_release "ente" "ente-io/ente" "prebuild" "cli-v0.2.3" "/opt/ente/cli/dist" "ente-cli-v0.2.3-linux-amd64.tar.gz"
$STD chmod +x /opt/ente/cli/dist/ente
msg_ok "Downloaded Ente CLI"

msg_info "Configuring Ente CLI"
$STD export ENTE_CLI_SECRETS_PATH=/opt/ente/cli/dist/secrets.txt
$STD export PATH="/opt/ente/cli/dist:$PATH"
cat <<EOF >>~/.bashrc
export ENTE_CLI_SECRETS_PATH=/opt/ente/cli/dist/secrets.txt
export PATH="/opt/ente/cli/dist:$PATH"
EOF
msg_ok "Exported Ente CLI paths"

cat <<EOF >~/.ente/config.yaml
endpoint:
    api: http://localhost:8080
EOF
msg_ok "Created Ente CLI config.yaml"

msg_ok "Configured Ente CLI"

msg_info "Building Museum (server)"
cd /opt/ente/server
$STD corepack enable
$STD go mod tidy
export CGO_ENABLED=1
CGO_CFLAGS="$(pkg-config --cflags libsodium || true)"
CGO_LDFLAGS="$(pkg-config --libs libsodium || true)"
if [ -z "$CGO_CFLAGS" ]; then
    CGO_CFLAGS="-I/usr/include"
fi
if [ -z "$CGO_LDFLAGS" ]; then
    CGO_LDFLAGS="-lsodium"
fi
export CGO_CFLAGS
export CGO_LDFLAGS
$STD go build cmd/museum/main.go
msg_ok "Built Museum"

msg_info "Generating Secrets"
SECRET_ENC=$($STD go run tools/gen-random-keys/main.go | grep "encryption" | awk '{print $2}')
SECRET_HASH=$($STD go run tools/gen-random-keys/main.go | grep "hash" | awk '{print $2}')
SECRET_JWT=$($STD go run tools/gen-random-keys/main.go | grep "jwt" | awk '{print $2}')
msg_ok "Generated Secrets"

msg_info "Creating museum.yaml"
cat <<EOF >/opt/ente/server/museum.yaml
db:
  host: 127.0.0.1
  port: 5432
  name: $DB_NAME
  user: $DB_USER
  password: $DB_PASS

s3:
  are_local_buckets: true
  use_path_style_urls: true
  local-dev:
    key: dummy
    secret: dummy
    endpoint: localhost:3200
    region: eu-central-2
    bucket: ente-dev

apps:
  public-albums: http://localhost:3002
  cast: http://localhost:3004
  accounts: http://localhost:3001

key:
  encryption: $SECRET_ENC
  hash: $SECRET_HASH

jwt:
  secret: $SECRET_JWT
EOF
msg_ok "Created museum.yaml"

# Prompt for backend URL
read -r -p "Enter the public URL for Ente backend (e.g., https://api.ente.yourdomain.com or http://192.168.1.100:8080) leave empty to use container IP: " backend_url
if [[ -z "$backend_url" ]]; then
    # Default to local IP if user doesn't provide one
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    ENTE_BACKEND_URL="http://$LOCAL_IP:8080"
    msg_info "No URL provided, using local IP: $ENTE_BACKEND_URL"
else
    ENTE_BACKEND_URL="$backend_url"
    msg_info "Using provided URL: $ENTE_BACKEND_URL"
fi

# Prompt for albums URL
read -r -p "Enter the public URL for Ente albums (e.g., https://albums.ente.yourdomain.com or http://192.168.1.100:3002) leave empty to use container IP: " albums_url
if [[ -z "$albums_url" ]]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    ENTE_ALBUMS_URL="http://$LOCAL_IP:3002"
    msg_info "No URL provided, using local IP: $ENTE_ALBUMS_URL"
else
    ENTE_ALBUMS_URL="$albums_url"
    msg_info "Using provided URL: $ENTE_ALBUMS_URL"
fi

export NEXT_PUBLIC_ENTE_ENDPOINT=$ENTE_BACKEND_URL
export NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT=$ENTE_ALBUMS_URL

# save to bashrc
cat <<EOF >>~/.bashrc
export NEXT_PUBLIC_ENTE_ENDPOINT=$ENTE_BACKEND_URL
export NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT=$ENTE_ALBUMS_URL
EOF
msg_ok "Saved to bashrc"

msg_info "Building Web Applications"
cd /opt/ente/web
$STD yarn install
$STD yarn build
$STD yarn build:accounts
$STD yarn build:auth
$STD yarn build:cast
mkdir -p /var/www/ente/apps
cp -r apps/photos/out /var/www/ente/apps/photos
cp -r apps/accounts/out /var/www/ente/apps/accounts
cp -r apps/auth/out /var/www/ente/apps/auth
cp -r apps/cast/out /var/www/ente/apps/cast
msg_ok "Built Web Applications"

msg_info "Creating Museum Service"
cat <<EOF >/etc/systemd/system/ente-museum.service
[Unit]
Description=Ente Museum Server
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/ente/server
ExecStart=/opt/ente/server/main -config /opt/ente/server/museum.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ente-museum
msg_ok "Created Museum Service"

msg_info "Configuring Caddy"
cat <<EOF >/etc/caddy/Caddyfile
:3000 {
    root * /var/www/ente/apps/photos
    file_server
    try_files {path} {path}.html /index.html
}
:3001 {
    root * /var/www/ente/apps/accounts
    file_server
    try_files {path} {path}.html /index.html
}
:3002 {
    root * /var/www/ente/apps/photos
    file_server
    try_files {path} {path}.html /index.html
}
:3003 {
    root * /var/www/ente/apps/auth
    file_server
    try_files {path} {path}.html /index.html
}
:3004 {
    root * /var/www/ente/apps/cast
    file_server
    try_files {path} {path}.html /index.html
}
EOF
systemctl reload caddy
msg_ok "Configured Caddy"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_info "If you want to use the Ente CLI, please follow the instructions at https://ente.io/help/self-hosting/administration/cli"
