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
  gcc \
  xxd
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

compute_email_hash() {
  local email_lower hash_b64 hash_hex
  email_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  hash_b64=$(awk '/^key:/{f=1;next} /^[^[:space:]]/{f=0} f && /hash:/{print $2}' /opt/ente/server/museum.yaml | tr -d '"'"'")
  hash_hex=$(printf '%s' "$hash_b64" | base64 -d | xxd -p -c 256 | tr -d '\n')
  printf '%s' "$email_lower" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$hash_hex" -binary | base64 -w0
}

echo "=== Ente First-Time Setup ==="
echo ""
read -r -p "Enter your account email: " EMAIL

if [[ -z "$EMAIL" ]]; then
  echo "Error: Email is required."
  exit 1
fi

echo ""
echo "Step 1/4: Register your account"
echo "  Open the web UI: http://${LOCAL_IP}:3000"
echo "  Create an account with: ${EMAIL}"
echo ""
echo "  Make sure you click 'Don't have an account?' and complete the signup form."
echo ""
read -r -p "Press ENTER after you submitted the signup form..."

echo ""
echo "Step 2/4: Getting verification code from logs..."
CODE=""
for i in 1 2 3; do
  sleep 3
  CODE=$(journalctl -u ente-museum --no-pager -n 200 | grep -oP 'Verification code: \K\d+' | tail -1)
  if [[ -n "$CODE" ]]; then
    break
  fi
  echo "  Attempt ${i}/3: Code not found yet, waiting..."
done

if [[ -n "$CODE" ]]; then
  echo ""
  echo "  Your verification code: ${CODE}"
  echo "  Enter this code in the web UI to complete registration."
else
  echo ""
  echo "  Could not find the verification code automatically."
  echo "  This usually means the signup form was not submitted yet."
  echo ""
  echo "  Are you sure you entered '${EMAIL}' and clicked 'Create account'?"
  echo "  You can check manually with: ente-get-verification"
fi
echo ""
read -r -p "Press ENTER after you verified the code in the web UI..."

echo ""
echo "Step 3/4: Looking up user and whitelisting admin..."
EMAIL_HASH=$(compute_email_hash "$EMAIL")
USER_ID=$(run_psql "SELECT user_id FROM users WHERE email_hash = '${EMAIL_HASH//\'/\'\'}';")

if [[ -z "$USER_ID" ]]; then
  echo "  Warning: User '${EMAIL}' not found in database."
  echo "  Make sure registration was completed successfully."
  echo ""
  echo "=== Setup incomplete ==="
  echo "After completing registration, run ente-setup again."
  exit 1
fi
echo "  Found user ID: ${USER_ID}"

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
  run_psql_exec "INSERT INTO subscriptions (user_id, storage_in_mbs_per_plan, expiry_time, product_id, payment_provider, transaction_id, original_transaction_id) VALUES (${USER_ID}, 10737418240, 2524608000000000, 'self_hosted_unlimited', 'admin', 'admin_setup', 'admin_setup');"
else
  run_psql_exec "UPDATE subscriptions SET storage_in_mbs_per_plan = 10737418240, expiry_time = 2524608000000000 WHERE user_id = ${USER_ID};"
fi
echo "  Subscription upgraded to unlimited storage."

echo ""
echo "=== Setup complete ==="
echo "Access Ente Photos at: http://${LOCAL_IP}:3000"
SETUPEOF
chmod +x /usr/local/bin/ente-setup

cat <<'EOF' >/usr/local/bin/ente-upgrade-subscription
#!/usr/bin/env bash
if [ -z "$1" ]; then
  echo "Usage: ente-upgrade-subscription <email>"
  echo "Example: ente-upgrade-subscription user@example.com"
  exit 1
fi
EMAIL="$1"
DB_NAME="ente_db"
EMAIL_LOWER=$(printf '%s' "$EMAIL" | tr '[:upper:]' '[:lower:]')
HASH_B64=$(awk '/^key:/{f=1;next} /^[^[:space:]]/{f=0} f && /hash:/{print $2}' /opt/ente/server/museum.yaml | tr -d '"'"'")
HASH_HEX=$(printf '%s' "$HASH_B64" | base64 -d | xxd -p -c 256 | tr -d '\n')
EMAIL_HASH=$(printf '%s' "$EMAIL_LOWER" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$HASH_HEX" -binary | base64 -w0)
echo "Upgrading subscription for: $EMAIL"
USER_ID=$(sudo -u postgres psql -t -d "$DB_NAME" -c "SELECT user_id FROM users WHERE email_hash = '${EMAIL_HASH//\'/\'\'}';")
USER_ID=$(echo "$USER_ID" | xargs)
if [[ -z "$USER_ID" ]]; then
  echo "Error: User not found in database."
  exit 1
fi
ROWS=$(sudo -u postgres psql -t -d "$DB_NAME" -c "SELECT count(*) FROM subscriptions WHERE user_id = ${USER_ID};" | xargs)
if [[ "$ROWS" == "0" ]]; then
  sudo -u postgres psql -d "$DB_NAME" -c "INSERT INTO subscriptions (user_id, storage_in_mbs_per_plan, expiry_time, product_id, payment_provider, transaction_id, original_transaction_id) VALUES (${USER_ID}, 10737418240, 2524608000000000, 'self_hosted_unlimited', 'admin', 'admin_setup', 'admin_setup');"
else
  sudo -u postgres psql -d "$DB_NAME" -c "UPDATE subscriptions SET storage_in_mbs_per_plan = 10737418240, expiry_time = 2524608000000000 WHERE user_id = ${USER_ID};"
fi
echo "Done. Subscription upgraded to unlimited storage for: $EMAIL"
EOF
chmod +x /usr/local/bin/ente-upgrade-subscription

msg_ok "Created helper scripts"

motd_ssh
customize
cleanup_lxc
