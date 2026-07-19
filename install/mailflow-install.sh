#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Author: Orange99
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://mailflow.sh/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
# Keep installer output clean even if caller enabled xtrace.
set +x
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

set_env_var() {
  local key="$1"
  local value="$2"
  python3 - "$key" "$value" <<'PY'
import sys
from pathlib import Path

key = sys.argv[1]
value = sys.argv[2]
path = Path('/opt/mailflow/.env')
lines = path.read_text().splitlines() if path.exists() else []
out = []
found = False

for line in lines:
    if line.startswith(f'{key}='):
        out.append(f'{key}={value}')
        found = True
    else:
        out.append(line)

if not found:
    out.append(f'{key}={value}')

path.write_text('\n'.join(out) + '\n')
PY
}

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  git \
  jq \
  openssl \
  ca-certificates \
  gnupg \
  lsb-release \
  apt-transport-https \
  build-essential \
  nginx \
  redis-server \
  python3
msg_ok "Installed Dependencies"

msg_info "Installing Node.js 20"
curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
$STD bash /tmp/nodesource_setup.sh
rm -f /tmp/nodesource_setup.sh
$STD apt-get update
$STD apt-get install -y \
  nodejs
msg_ok "Installed Node.js"

msg_info "Installing PostgreSQL 16"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
chmod a+r /etc/apt/keyrings/postgresql.gpg
echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
$STD apt-get update
$STD apt-get install -y \
  postgresql-16 \
  postgresql-client-16
$STD systemctl enable --now postgresql redis-server nginx
msg_ok "Installed PostgreSQL, Redis and nginx"

msg_info "Setting up MailFlow"
mkdir -p /opt/mailflow
cd /opt/mailflow || exit 1

RELEASE=$(curl -fsSL https://api.github.com/repos/maathimself/mailflow/releases/latest | jq -r '.tag_name // empty')
if [[ -z "${RELEASE}" ]]; then
  msg_warn "Could not detect latest release tag, falling back to main"
  RELEASE="main"
fi

if [[ -d .git ]]; then
  msg_info "Updating repository metadata"
  $STD git fetch --all --tags --force
else
  msg_info "Cloning MailFlow"
  $STD git clone --depth 1 --branch "$RELEASE" https://github.com/maathimself/mailflow.git . \
    || $STD git clone --depth 1 https://github.com/maathimself/mailflow.git .
fi

if git rev-parse --verify "$RELEASE" >/dev/null 2>&1; then
  $STD git checkout -f "$RELEASE"
else
  $STD git checkout -f main
fi
msg_ok "Repository ready at ${RELEASE}"

msg_info "Configuring MailFlow"
SESSION_SECRET=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
IP=$(hostname -I | awk '{print $1}')

cp -f .env.example .env

set_env_var APP_URL "https://${IP}"
set_env_var FRONTEND_URL "https://${IP}"
set_env_var SESSION_SECRET "$SESSION_SECRET"
set_env_var DB_HOST "127.0.0.1"
set_env_var DB_PORT "5432"
set_env_var DB_NAME "mailflow"
set_env_var DB_USER "mailflow"
set_env_var DB_PASSWORD "$DB_PASSWORD"
set_env_var REDIS_URL "redis://127.0.0.1:6379"
set_env_var ENCRYPTION_KEY "$ENCRYPTION_KEY"
set_env_var PORT "3000"
set_env_var NODE_ENV "production"
set_env_var APP_VERSION "$RELEASE"
set_env_var BUILD_SHA "$(git rev-parse --short HEAD)"


msg_info "Creating PostgreSQL database"
PSQL="sudo -u postgres psql -v ON_ERROR_STOP=1"
if ! $STD $PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname='mailflow'" | grep -q 1; then
  $STD $PSQL -c "CREATE USER mailflow WITH PASSWORD '${DB_PASSWORD}';"
else
  $STD $PSQL -c "ALTER USER mailflow WITH PASSWORD '${DB_PASSWORD}';"
fi

if ! $STD $PSQL -tAc "SELECT 1 FROM pg_database WHERE datname='mailflow'" | grep -q 1; then
  $STD $PSQL -c "CREATE DATABASE mailflow OWNER mailflow;"
else
  $STD $PSQL -c "ALTER DATABASE mailflow OWNER TO mailflow;"
fi

# Grant all privileges to mailflow user
$STD $PSQL -d mailflow -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO mailflow;"
$STD $PSQL -d mailflow -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO mailflow;"
$STD $PSQL -d mailflow -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO mailflow;"
$STD $PSQL -d mailflow -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO mailflow;"
msg_ok "Created PostgreSQL database"

msg_info "Building frontend"
cd /opt/mailflow/frontend || exit 1
$STD npm ci
$STD npm run build
msg_ok "Built frontend"

msg_info "Installing backend dependencies"
cd /opt/mailflow/backend || exit 1
$STD npm ci --omit=dev
msg_ok "Installed backend dependencies"

msg_info "Configuring nginx and TLS"
mkdir -p /etc/ssl/mailflow
openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
  -keyout /etc/ssl/mailflow/key.pem \
  -out /etc/ssl/mailflow/cert.pem \
  -subj "/CN=${IP}" >/dev/null 2>&1

cat >/etc/nginx/sites-available/mailflow <<'EOF'
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate     /etc/ssl/mailflow/cert.pem;
    ssl_certificate_key /etc/ssl/mailflow/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    root /opt/mailflow/frontend/dist;
    index index.html;

    client_max_body_size 50m;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data: https:; img-src 'self' data: https: blob:; connect-src 'self' wss: ws:; frame-src 'self'; object-src 'none'; base-uri 'self';" always;

    location /oauth/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 30s;
    }

    location /auth/oidc/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 30s;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 60s;
    }

    location /ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400s;
    }

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-store" always;
    }

    location = /sw.js {
        add_header Cache-Control "no-store" always;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

ln -sf /etc/nginx/sites-available/mailflow /etc/nginx/sites-enabled/mailflow
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
$STD systemctl restart nginx

msg_info "Skipping manual DB migrations"
msg_ok "MailFlow applies schema updates automatically on first startup"

msg_info "Installing systemd service"
cat >/etc/systemd/system/mailflow.service <<'EOF'
[Unit]
Description=MailFlow backend
Documentation=https://github.com/maathimself/mailflow
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/mailflow/backend
EnvironmentFile=/opt/mailflow/.env
ExecStart=/usr/bin/node src/index.js
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/mailflow

[Install]
WantedBy=multi-user.target
EOF

chown -R www-data:www-data /opt/mailflow
chmod 640 /opt/mailflow/.env
systemctl daemon-reload
$STD systemctl enable --now mailflow
msg_ok "Configured MailFlow"

msg_info "Starting MailFlow"
systemctl restart mailflow
sleep 3
if systemctl is-active --quiet mailflow; then
  msg_ok "Started MailFlow"
else
  msg_info "MailFlow service failed to start. Checking logs..."
  systemctl status mailflow || true
  journalctl -u mailflow -n 50 --no-pager || true
  exit 1
fi


msg_info "Cleaning up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned"

exit 0

