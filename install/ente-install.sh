#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
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
$STD apt install -y \
  libsodium23 \
  libsodium-dev \
  pkg-config \
  caddy \
  gcc
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="ente_db" PG_DB_USER="ente" setup_postgresql_db
setup_go
NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs
RUST_CRATES="wasm-pack" setup_rust
$STD rustup target add wasm32-unknown-unknown
import_local_ip

ENTE_CLI_VERSION=$(curl -s https://api.github.com/repos/ente-io/ente/releases | jq -r '[.[] | select(.tag_name | startswith("cli-v"))][0].tag_name')
fetch_and_deploy_gh_release "ente-server" "ente-io/ente" "tarball" "latest" "/opt/ente"
fetch_and_deploy_gh_release "ente-cli" "ente-io/ente" "prebuild" "$ENTE_CLI_VERSION" "/usr/local/bin" "ente-$ENTE_CLI_VERSION-linux-amd64.tar.gz"

$STD mkdir -p /opt/ente/cli
msg_info "Configuring Ente CLI"
cat <<EOF >>~/.bashrc
export ENTE_CLI_SECRETS_PATH=/opt/ente/cli/secrets.txt
export PATH="/usr/local/bin:$PATH"
EOF
$STD source ~/.bashrc
$STD mkdir -p ~/.ente
cat <<EOF >~/.ente/config.yaml
endpoint:
    api: http://localhost:8080
EOF
msg_ok "Configured Ente CLI"

msg_info "Saving Ente Credentials"
{
  echo "Important Configuration Notes:"
  echo "- Frontend is built with IP: $LOCAL_IP"
  echo "- If IP changes, run: /opt/ente/rebuild-frontend.sh"
  echo "- Museum API: http://$LOCAL_IP:8080"
  echo "- Photos UI: http://$LOCAL_IP:3000"
  echo "- Accounts UI: http://$LOCAL_IP:3001"
  echo "- Auth UI: http://$LOCAL_IP:3003"
  echo ""
  echo "Post-Installation Steps Required:"
  echo "1. Create your first user account via the web UI"
  echo "2. Check museum logs for email verification code:"
  echo "   journalctl -u ente-museum -n 100 | grep -i 'verification'"
  echo "3. Use verification code to complete account setup"
  echo "4. Remove subscription limit (replace <email> with your account):"
  echo "   ente admin update-subscription -a <email> -u <email> --no-limit"
  echo ""
  echo "Note: Email verification requires manual intervention since SMTP is not configured"
} >>~/ente.creds
msg_ok "Saved Ente Credentials"

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
SECRET_ENC=$(go run tools/gen-random-keys/main.go 2>/dev/null | grep "encryption" | awk '{print $2}')
SECRET_HASH=$(go run tools/gen-random-keys/main.go 2>/dev/null | grep "hash" | awk '{print $2}')
SECRET_JWT=$(go run tools/gen-random-keys/main.go 2>/dev/null | grep "jwt" | awk '{print $2}')
msg_ok "Generated Secrets"

msg_info "Creating museum.yaml"
cat <<EOF >/opt/ente/server/museum.yaml
db:
  host: 127.0.0.1
  port: 5432
  name: $PG_DB_NAME
  user: $PG_DB_USER
  password: $PG_DB_PASS

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
  public-albums: http://${LOCAL_IP}:3002
  cast: http://${LOCAL_IP}:3004
  accounts: http://${LOCAL_IP}:3001

key:
  encryption: $SECRET_ENC
  hash: $SECRET_HASH

jwt:
  secret: $SECRET_JWT

# SMTP not configured - verification codes will appear in logs
# To configure SMTP, add:
# smtp:
#   host: your-smtp-server
#   port: 587
#   username: your-username
#   password: your-password
#   email: noreply@yourdomain.com
EOF
msg_ok "Created museum.yaml"

read -r -p "Enter the public URL for Ente backend (e.g., https://api.ente.yourdomain.com or http://192.168.1.100:8080) leave empty to use container IP: " backend_url
if [[ -z "$backend_url" ]]; then
  ENTE_BACKEND_URL="http://$LOCAL_IP:8080"
  msg_info "No URL provided"
  msg_ok "using local IP: $ENTE_BACKEND_URL\n"
else
  ENTE_BACKEND_URL="$backend_url"
  msg_info "URL provided"
  msg_ok "Using provided URL: $ENTE_BACKEND_URL\n"
fi

read -r -p "Enter the public URL for Ente albums (e.g., https://albums.ente.yourdomain.com or http://192.168.1.100:3002) leave empty to use container IP: " albums_url
if [[ -z "$albums_url" ]]; then
  ENTE_ALBUMS_URL="http://$LOCAL_IP:3002"
  msg_info "No URL provided"
  msg_ok "using local IP: $ENTE_ALBUMS_URL\n"
else
  ENTE_ALBUMS_URL="$albums_url"
  msg_info "URL provided"
  msg_ok "Using provided URL: $ENTE_ALBUMS_URL\n"
fi

export NEXT_PUBLIC_ENTE_ENDPOINT=$ENTE_BACKEND_URL
export NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT=$ENTE_ALBUMS_URL

msg_info "Building Web Applications"
cd /opt/ente/web
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
source "$HOME/.cargo/env"
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

cat <<'EOF' >/opt/ente/rebuild-frontend.sh
#!/usr/bin/env bash
# Rebuild Ente frontend
# Prompt for backend URL
read -r -p "Enter the public URL for Ente backend (e.g., https://api.ente.yourdomain.com or http://192.168.1.100:8080) leave empty to use container IP: " backend_url
if [[ -z "$backend_url" ]]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    ENTE_BACKEND_URL="http://$LOCAL_IP:8080"
    echo "No URL provided, using local IP: $ENTE_BACKEND_URL"
else
    ENTE_BACKEND_URL="$backend_url"
    echo "Using provided URL: $ENTE_BACKEND_URL"
fi

# Prompt for albums URL
read -r -p "Enter the public URL for Ente albums (e.g., https://albums.ente.yourdomain.com or http://192.168.1.100:3002) leave empty to use container IP: " albums_url
if [[ -z "$albums_url" ]]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    ENTE_ALBUMS_URL="http://$LOCAL_IP:3002"
    echo "No URL provided, using local IP: $ENTE_ALBUMS_URL"
else
    ENTE_ALBUMS_URL="$albums_url"
    echo "Using provided URL: $ENTE_ALBUMS_URL"
fi

export NEXT_PUBLIC_ENTE_ENDPOINT=$ENTE_BACKEND_URL
export NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT=$ENTE_ALBUMS_URL

echo "Building Web Applications..."

# Ensure Rust/wasm-pack is available for WASM build
source "$HOME/.cargo/env"
cd /opt/ente/web
yarn build
yarn build:accounts
yarn build:auth
yarn build:cast
rm -rf /var/www/ente/apps/*
cp -r apps/photos/out /var/www/ente/apps/photos
cp -r apps/accounts/out /var/www/ente/apps/accounts
cp -r apps/auth/out /var/www/ente/apps/auth
cp -r apps/cast/out /var/www/ente/apps/cast
systemctl reload caddy
echo "Frontend rebuilt successfully!"
EOF
chmod +x /opt/ente/rebuild-frontend.sh
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
# Ente Photos - Main Application
:3000 {
    root * /var/www/ente/apps/photos
    file_server
    try_files {path} {path}.html /index.html

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers *
    }
}

# Ente Accounts
:3001 {
    root * /var/www/ente/apps/accounts
    file_server
    try_files {path} {path}.html /index.html

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers *
    }
}

# Public Albums
:3002 {
    root * /var/www/ente/apps/photos
    file_server
    try_files {path} {path}.html /index.html

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers *
    }
}

# Auth
:3003 {
    root * /var/www/ente/apps/auth
    file_server
    try_files {path} {path}.html /index.html

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers *
    }
}

# Cast
:3004 {
    root * /var/www/ente/apps/cast
    file_server
    try_files {path} {path}.html /index.html

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers *
    }
}

# Museum API Proxy
:8080 {
    reverse_proxy localhost:8080

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers *
    }
}
EOF
systemctl reload caddy
msg_ok "Configured Caddy"

msg_info "Creating helper scripts"
cat <<'EOF' >/usr/local/bin/ente-get-verification
#!/usr/bin/env bash
echo "Searching for verification codes in museum logs..."
journalctl -u ente-museum --no-pager | grep -i "verification\|verify\|code" | tail -20
EOF
chmod +x /usr/local/bin/ente-get-verification

cat <<'EOF' >/usr/local/bin/ente-upgrade-subscription
#!/usr/bin/env bash
if [ -z "$1" ]; then
    echo "Usage: ente-upgrade-subscription <email>"
    echo "Example: ente-upgrade-subscription user@example.com"
    exit 1
fi
EMAIL="$1"
echo "Upgrading subscription for: $EMAIL"
ente admin update-subscription -a "$EMAIL" -u "$EMAIL" --no-limit
EOF
chmod +x /usr/local/bin/ente-upgrade-subscription

msg_ok "Created helper scripts"

motd_ssh
customize
cleanup_lxc
