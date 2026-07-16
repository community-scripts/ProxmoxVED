#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ProxmoxVED Community
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://aliasvault.net

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  python3 \
  build-essential \
  gettext-base \
  inotify-tools \
  libkrb5-3 \
  libgssapi-krb5-2 \
  openssl
# Ensure cc linker is available — update-alternatives may not run in minimal LXC
[[ ! -e /usr/bin/cc ]] && ln -sf /usr/bin/gcc /usr/local/bin/cc
msg_ok "Installed Dependencies"

setup_rust
fetch_and_deploy_gh_release "wasm-pack" "rustwasm/wasm-pack" "prebuild" "latest" "/usr/local/bin" "wasm-pack-v*-x86_64-unknown-linux-musl.tar.gz"

NODE_VERSION="20" setup_nodejs

msg_info "Installing .NET SDK 10.0"
setup_deb822_repo "microsoft-prod" \
  "https://packages.microsoft.com/keys/microsoft.asc" \
  "https://packages.microsoft.com/debian/12/prod" \
  "bookworm" \
  "main" \
  "amd64"
$STD apt install -y dotnet-sdk-10.0
msg_ok "Installed .NET SDK 10.0"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="aliasvault" PG_DB_USER="aliasvault" setup_postgresql_db

fetch_and_deploy_gh_release "aliasvault" "aliasvault/aliasvault" "tarball"

msg_info "Building Core Libraries (Patience)"
source "$HOME/.cargo/env"
$STD rustup target add wasm32-unknown-unknown
cd /opt/aliasvault/core
# Upstream ships year-hardcoded tests (AgeRangeConverter) that fail after 2025-12-31
# and abort the build via `set -e` + `npm run test && npm run build`. Strip the
# test step from per-package build.sh so the actual build always runs.
find /opt/aliasvault/core -name build.sh -exec sed -i 's/npm run test &&[[:space:]]*//g' {} +
$STD bash build-and-distribute.sh --browser
msg_ok "Built Core Libraries"

msg_info "Copying Core Artifacts"
mkdir -p /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/wasm
cp /opt/aliasvault/core/rust/dist/wasm/aliasvault_core_bg.wasm \
  /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/wasm/
cp /opt/aliasvault/core/rust/dist/wasm/aliasvault_core.js \
  /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/wasm/
mkdir -p /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/js/dist/core/{identity-generator,vault}
cp -r /opt/aliasvault/core/typescript/identity-generator/dist/. \
  /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/js/dist/core/identity-generator/
cp -r /opt/aliasvault/core/vault/dist/. \
  /opt/aliasvault/apps/server/AliasVault.Client/wwwroot/js/dist/core/vault/
msg_ok "Copied Core Artifacts"

msg_info "Building AliasVault Applications (Patience)"
cd /opt/aliasvault/apps/server
$STD dotnet workload install wasm-tools
$STD dotnet restore aliasvault.sln
$STD dotnet publish AliasVault.Api/AliasVault.Api.csproj \
  -c Release -o /opt/aliasvault/api --no-restore
$STD dotnet build AliasVault.Client/AliasVault.Client.csproj \
  -c Release --no-restore
$STD dotnet publish AliasVault.Client/AliasVault.Client.csproj \
  -c Release -o /opt/aliasvault/client --no-restore
# Clear the hardcoded localhost:5092 API URL so the client uses its own origin + /api/
# Also remove pre-compressed copies so nginx (gzip_static on) serves the patched file
python3 -c "
import json, pathlib
p = pathlib.Path('/opt/aliasvault/client/wwwroot/appsettings.json')
c = json.loads(p.read_text()); c['ApiUrl'] = ''; p.write_text(json.dumps(c, indent=2))
for ext in ['.gz', '.br']:
    q = pathlib.Path(str(p) + ext)
    if q.exists(): q.unlink()
"
$STD dotnet publish AliasVault.Admin/AliasVault.Admin.csproj \
  -c Release -o /opt/aliasvault/admin --no-restore
$STD dotnet publish Services/AliasVault.SmtpService/AliasVault.SmtpService.csproj \
  -c Release -o /opt/aliasvault/smtp --no-restore
$STD dotnet publish Services/AliasVault.TaskRunner/AliasVault.TaskRunner.csproj \
  -c Release -o /opt/aliasvault/taskrunner --no-restore
$STD dotnet publish Utilities/AliasVault.InstallCli/AliasVault.InstallCli.csproj \
  -c Release -o /opt/aliasvault/installcli --no-restore
msg_ok "Built AliasVault Applications"

msg_info "Generating Secrets and Configuration"
ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
ADMIN_HASH=$(dotnet /opt/aliasvault/installcli/AliasVault.InstallCli.dll hash-password "$ADMIN_PASS")
ADMIN_GENERATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
JWT_KEY=$(openssl rand -base64 32)
DATA_PROTECTION_CERT_PASS=$(openssl rand -base64 32)
DB_CONN="Host=localhost;Port=5432;Database=aliasvault;Username=aliasvault;Password=${PG_DB_PASS};Maximum Pool Size=80;Minimum Pool Size=5"
cat <<EOF >/opt/aliasvault/.env
ConnectionStrings__AliasServerDbContext=${DB_CONN}
JWT_KEY=${JWT_KEY}
DATA_PROTECTION_CERT_PASS=${DATA_PROTECTION_CERT_PASS}
ADMIN_PASSWORD_HASH=${ADMIN_HASH}
ADMIN_PASSWORD_GENERATED=${ADMIN_GENERATED}
PUBLIC_REGISTRATION_ENABLED=true
IP_LOGGING_ENABLED=true
PRIVATE_EMAIL_DOMAINS=
HIDDEN_PRIVATE_EMAIL_DOMAINS=
MAX_UPLOAD_SIZE_MB=100
SMTP_TLS_ENABLED=false
Logging__LogLevel__Default=Error
Logging__LogLevel__Microsoft__Hosting__Lifetime=Error
Logging__LogLevel__Microsoft=Error
EOF
chmod 600 /opt/aliasvault/.env
msg_ok "Generated Secrets and Configuration"

msg_info "Generating SSL Certificate"
mkdir -p /opt/aliasvault/certificates/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /opt/aliasvault/certificates/ssl/key.pem \
  -out /opt/aliasvault/certificates/ssl/cert.pem \
  -subj "/C=US/ST=State/L=City/O=AliasVault/CN=${LOCAL_IP}" \
  -addext "subjectAltName=IP:${LOCAL_IP},DNS:localhost,IP:127.0.0.1" \
  2>/dev/null
chmod 600 /opt/aliasvault/certificates/ssl/key.pem
chmod 644 /opt/aliasvault/certificates/ssl/cert.pem
msg_ok "Generated SSL Certificate"

msg_info "Configuring Nginx"
rm -f /etc/nginx/sites-enabled/default
cat <<'NGINXEOF' >/etc/nginx/sites-available/aliasvault
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream aliasvault_api   { server 127.0.0.1:3001 max_fails=1 fail_timeout=5s; }
upstream aliasvault_admin { server 127.0.0.1:3002 max_fails=1 fail_timeout=5s; }

server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name _;

    ssl_certificate     /opt/aliasvault/certificates/ssl/cert.pem;
    ssl_certificate_key /opt/aliasvault/certificates/ssl/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    client_max_body_size 100M;

    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # .mjs files must be served as text/javascript for dynamic import() to work
    types {
        application/javascript mjs;
    }

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/wasm;

    # API
    location /api {
        proxy_pass http://aliasvault_api;
        proxy_set_header Host              $http_host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_intercept_errors on;
        error_page 502 503 504 =503 @unavailable;
    }

    # Admin (Blazor Server — needs WebSocket)
    location /admin {
        proxy_pass http://aliasvault_admin;
        proxy_set_header Host                $http_host;
        proxy_set_header X-Real-IP           $remote_addr;
        proxy_set_header X-Forwarded-Proto   $scheme;
        proxy_set_header X-Forwarded-For     $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Prefix  /admin/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 86400;
        proxy_intercept_errors on;
        error_page 502 503 504 =503 @unavailable;
    }

    # Blazor WASM client (static files)
    root /opt/aliasvault/client/wwwroot;
    location / {
        gzip_static on;
        try_files $uri $uri/ /index.html =404;
    }

    location @unavailable {
        return 503 "Service temporarily unavailable";
    }
}
NGINXEOF
ln -sf /etc/nginx/sites-available/aliasvault /etc/nginx/sites-enabled/aliasvault
$STD nginx -t
systemctl enable -q --now nginx
$STD nginx -s reload
msg_ok "Configured Nginx"

mkdir -p /opt/certificates/app

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/aliasvault-api.service
[Unit]
Description=AliasVault API
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/api
EnvironmentFile=/opt/aliasvault/.env
Environment=ASPNETCORE_URLS=http://127.0.0.1:3001
Environment=ASPNETCORE_PATHBASE=/api
ExecStart=/usr/bin/dotnet AliasVault.Api.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/aliasvault-admin.service
[Unit]
Description=AliasVault Admin
After=network.target aliasvault-api.service
Wants=aliasvault-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/admin
EnvironmentFile=/opt/aliasvault/.env
Environment=ASPNETCORE_URLS=http://127.0.0.1:3002
Environment=ASPNETCORE_PATHBASE=/admin
ExecStart=/usr/bin/dotnet AliasVault.Admin.dll
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/aliasvault-smtp.service
[Unit]
Description=AliasVault SMTP Service
After=network.target aliasvault-api.service
Requires=aliasvault-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/smtp
EnvironmentFile=/opt/aliasvault/.env
ExecStart=/usr/bin/dotnet AliasVault.SmtpService.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/aliasvault-taskrunner.service
[Unit]
Description=AliasVault Task Runner
After=network.target aliasvault-api.service
Requires=aliasvault-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/taskrunner
EnvironmentFile=/opt/aliasvault/.env
ExecStart=/usr/bin/dotnet AliasVault.TaskRunner.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now aliasvault-api aliasvault-admin aliasvault-smtp aliasvault-taskrunner
msg_ok "Created Services"

{
  echo ""
  echo "AliasVault Admin Credentials:"
  echo "  Username: admin"
  echo "  Password: ${ADMIN_PASS}"
} >>~/aliasvault.creds

motd_ssh
customize
cleanup_lxc
