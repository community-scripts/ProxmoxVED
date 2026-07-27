#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
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

fetch_and_deploy_gh_release "ente-server" "ente-io/ente" "tarball" "latest" "/opt/ente"

msg_info "Building Ente CLI"
cd /opt/ente/cli
$STD go build -o /usr/local/bin/ente .
chmod +x /usr/local/bin/ente
msg_ok "Built Ente CLI"

$STD mkdir -p /opt/ente/cli-config
msg_info "Configuring Ente CLI"
cat <<EOF >>~/.bashrc
export ENTE_CLI_SECRETS_PATH=/opt/ente/cli-config/secrets.txt
export PATH="/usr/local/bin:$PATH"
EOF
$STD source ~/.bashrc
$STD mkdir -p ~/.ente
cat <<EOF >~/.ente/config.yaml
endpoint:
    api: http://localhost:8080
EOF
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
SECRET_ENC=$(go run tools/gen-random-keys/main.go 2>/dev/null | grep "encryption" | awk '{print $2}')
SECRET_HASH=$(go run tools/gen-random-keys/main.go 2>/dev/null | grep "hash" | awk '{print $2}')
SECRET_JWT=$(go run tools/gen-random-keys/main.go 2>/dev/null | grep "jwt" | awk '{print $2}')
msg_ok "Generated Secrets"

msg_info "Installing MinIO"
MINIO_PASS=$(openssl rand -base64 18)
curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio
chmod +x /usr/local/bin/minio
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc
mkdir -p /opt/minio/data
cat <<EOF >/etc/default/minio
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_PASS}
MINIO_VOLUMES=/opt/minio/data
MINIO_OPTS="--address :3200 --console-address :3201"
EOF
cat <<'EOF' >/etc/systemd/system/minio.service
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_VOLUMES $MINIO_OPTS
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now minio
sleep 5
$STD mc alias set local http://127.0.0.1:3200 minioadmin "${MINIO_PASS}"
$STD mc mb --ignore-existing local/b2-eu-cen
$STD mc mb --ignore-existing local/wasabi-eu-central-2-v3
$STD mc mb --ignore-existing local/scw-eu-fr-v3
msg_ok "Installed MinIO"

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
  b2-eu-cen:
    key: minioadmin
    secret: $MINIO_PASS
    endpoint: ${LOCAL_IP}:3200
    region: eu-central-2
    bucket: b2-eu-cen
  wasabi-eu-central-2-v3:
    key: minioadmin
    secret: $MINIO_PASS
    endpoint: ${LOCAL_IP}:3200
    region: eu-central-2
    bucket: wasabi-eu-central-2-v3
    compliance: false
  scw-eu-fr-v3:
    key: minioadmin
    secret: $MINIO_PASS
    endpoint: ${LOCAL_IP}:3200
    region: eu-central-2
    bucket: scw-eu-fr-v3

apps:
  public-albums: http://${LOCAL_IP}:3002
  cast: http://${LOCAL_IP}:3004
  accounts: http://${LOCAL_IP}:3001

key:
  encryption: $SECRET_ENC
  hash: $SECRET_HASH

jwt:
  secret: $SECRET_JWT
EOF
msg_ok "Created museum.yaml"

read -r -p "${TAB3}Enter the public URL for Ente backend (e.g., https://api.ente.yourdomain.com or http://192.168.1.100:8080) leave empty to use container IP: " backend_url
if [[ -z "$backend_url" ]]; then
  ENTE_BACKEND_URL="http://$LOCAL_IP:8080"
  msg_info "No URL provided"
  msg_ok "using local IP: $ENTE_BACKEND_URL\n"
else
  ENTE_BACKEND_URL="$backend_url"
  msg_info "URL provided"
  msg_ok "Using provided URL: $ENTE_BACKEND_URL\n"
fi

read -r -p "${TAB3}Enter the public URL for Ente albums (e.g., https://albums.ente.yourdomain.com or http://192.168.1.100:3002) leave empty to use container IP: " albums_url
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

EOF
systemctl reload caddy
msg_ok "Configured Caddy"

msg_info "Creating helper scripts"
cat <<'EOF' >/usr/local/bin/ente-get-verification
#!/usr/bin/env bash
echo "Searching for verification codes in museum logs..."
journalctl -u ente-museum --no-pager | grep -oP 'Verification code: \K\d+' | tail -5
if [[ -z "$(journalctl -u ente-museum --no-pager | grep -oP 'Verification code: \K\d+' | tail -1)" ]]; then
  echo "No codes found. Showing recent relevant logs:"
  journalctl -u ente-museum --no-pager -n 50 | grep -iE "verification|ott|code|Skipping sending" | tail -20
fi
EOF
chmod +x /usr/local/bin/ente-get-verification

cat <<'SETUPEOF' >/usr/local/bin/ente-setup
#!/usr/bin/env bash
LOCAL_IP=$(hostname -I | awk '{print $1}')
DB_NAME="ente_db"

run_psql() {
  sudo -u postgres psql -t -d "$DB_NAME" -c "$1" 2>/dev/null | xargs
}

run_psql_exec() {
  sudo -u postgres psql -d "$DB_NAME" -c "$1" 2>/dev/null
}

echo "=== Ente First-Time Setup ==="
echo ""
echo "Step 1/4: Register your account"
echo "  Open the web UI: http://${LOCAL_IP}:3000"
echo "  Click 'Don't have an account?' and submit the signup form."
echo ""
read -r -p "Press ENTER after you submitted the signup form..."

echo ""
echo "Step 2/4: Getting verification code from logs..."
CODE=""
for i in 1 2 3; do
  sleep 3
  CODE=$(journalctl -u ente-museum --no-pager -n 200 | grep -oP 'Verification code: \K\d+' | tail -1)
  [[ -n "$CODE" ]] && break
  echo "  Attempt ${i}/3: Code not found yet, waiting..."
done

if [[ -n "$CODE" ]]; then
  echo ""
  echo "  Your verification code: ${CODE}"
  echo "  Enter this code in the web UI and finish the key/passphrase setup."
else
  echo ""
  echo "  Could not find a verification code automatically."
  echo "  Run 'ente-get-verification' manually if needed."
fi
echo ""
read -r -p "Press ENTER once registration is fully complete in the web UI..."

echo ""
echo "Step 3/4: Locating your user account..."
USER_COUNT=$(run_psql "SELECT count(*) FROM users;")
if [[ "$USER_COUNT" == "0" ]]; then
  echo "  No users found in the database."
  echo "  Registration was not completed. Run 'ente-setup' again after signup."
  exit 1
fi

USER_ID=$(run_psql "SELECT user_id FROM users ORDER BY user_id DESC LIMIT 1;")
echo "  Using most recently registered user (id: ${USER_ID})."
echo ""
echo "  All users in database:"
run_psql_exec "SELECT user_id, creation_time FROM users ORDER BY user_id DESC;"
echo ""
read -r -p "Press ENTER to whitelist user ${USER_ID} as admin (or Ctrl-C to abort)..."

if grep -q "internal:" /opt/ente/server/museum.yaml; then
  if ! grep -qF "${USER_ID}" /opt/ente/server/museum.yaml; then
    sed -i "/admins:/a\\    - ${USER_ID}" /opt/ente/server/museum.yaml
  fi
else
  cat <<ADMEOF >>/opt/ente/server/museum.yaml

internal:
  admins:
    - ${USER_ID}
ADMEOF
fi
systemctl restart ente-museum
sleep 2
echo "  Admin whitelisted."

echo ""
echo "Step 4/4: Upgrading subscription..."
ROWS=$(run_psql "SELECT count(*) FROM subscriptions WHERE user_id = ${USER_ID};")
if [[ "$ROWS" == "0" ]]; then
  run_psql_exec "INSERT INTO subscriptions (user_id, storage, expiry_time, product_id, payment_provider, original_transaction_id, attributes) VALUES (${USER_ID}, 10995116277760, 2524608000000000, 'self_hosted_unlimited', 'admin', 'admin_setup', '{}'::jsonb);"
else
  run_psql_exec "UPDATE subscriptions SET storage = 10995116277760, expiry_time = 2524608000000000 WHERE user_id = ${USER_ID};"
fi
echo "  Subscription upgraded to unlimited storage."

echo ""
echo "=== Setup complete ==="
echo "Access Ente Photos at: http://${LOCAL_IP}:3000"
SETUPEOF
chmod +x /usr/local/bin/ente-setup

cat <<'EOF' >/usr/local/bin/ente-upgrade-subscription
#!/usr/bin/env bash
DB_NAME="ente_db"

run_psql() {
  sudo -u postgres psql -t -d "$DB_NAME" -c "$1" 2>/dev/null | xargs
}

run_psql_exec() {
  sudo -u postgres psql -d "$DB_NAME" -c "$1"
}

if [[ -z "$1" ]]; then
  echo "Usage: ente-upgrade-subscription <user_id>"
  echo ""
  echo "Available users:"
  run_psql_exec "SELECT user_id, creation_time FROM users ORDER BY user_id DESC;"
  exit 1
fi

USER_ID="$1"
if ! [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: user_id must be numeric."
  exit 1
fi

EXISTS=$(run_psql "SELECT count(*) FROM users WHERE user_id = ${USER_ID};")
if [[ "$EXISTS" != "1" ]]; then
  echo "Error: user_id ${USER_ID} not found."
  exit 1
fi

ROWS=$(run_psql "SELECT count(*) FROM subscriptions WHERE user_id = ${USER_ID};")
if [[ "$ROWS" == "0" ]]; then
  run_psql_exec "INSERT INTO subscriptions (user_id, storage, expiry_time, product_id, payment_provider, original_transaction_id, attributes) VALUES (${USER_ID}, 10995116277760, 2524608000000000, 'self_hosted_unlimited', 'admin', 'admin_setup', '{}'::jsonb);"
else
  run_psql_exec "UPDATE subscriptions SET storage = 10995116277760, expiry_time = 2524608000000000 WHERE user_id = ${USER_ID};"
fi
echo "Done. Subscription upgraded to unlimited storage for user_id ${USER_ID}."
EOF
chmod +x /usr/local/bin/ente-upgrade-subscription

msg_ok "Created helper scripts"

motd_ssh
customize
cleanup_lxc
