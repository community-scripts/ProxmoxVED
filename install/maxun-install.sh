#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  gpg \
  openssl \
  redis \
  libgbm1 \
  libnss3 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libdrm2 \
  libxkbcommon0 \
  libglib2.0-0 \
  libdbus-1-3 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxi6 \
  libxtst6 \
  ca-certificates \
  libxrandr2 \
  libasound2 \
  libxss1 \
  libxinerama1 \
  nginx
msg_ok "Installed Dependencies"

#configure_lxc "Semantic Search requires a dedicated GPU and at least 16GB RAM. Would you like to install it?" 100 "memory" "16000"

PG_VERSION=17 install_postgresql
NODE_VERSION="22" install_node_and_modules

msg_info "Setup Variables"
DB_NAME=maxun_db
DB_USER=maxun_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
MINIO_USER=minio_usr
MINIO_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
LOCAL_IP=$(hostname -I | awk '{print $1}')
msg_ok "Set up Variables"

msg_info "Setup Database"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "Maxun-Credentials"
  echo "Maxun Database User: $DB_USER"
  echo "Maxun Database Password: $DB_PASS"
  echo "Maxun Database Name: $DB_NAME"
  echo "Maxun JWT Secret: $JWT_SECRET"
  echo "Maxun Encryption Key: $ENCRYPTION_KEY"
} >>~/maxun.creds
msg_ok "Set up Database"

msg_info "Setup MinIO"
cd /tmp
wget -q https://dl.min.io/server/minio/release/linux-amd64/minio
mv minio /usr/local/bin/
chmod +x /usr/local/bin/minio
mkdir -p /data
cat <<EOF >/etc/systemd/system/minio.service
[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target

[Service]
User=root
EnvironmentFile=-/etc/default/minio
ExecStart=/usr/local/bin/minio server /data
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
{
  echo "__________________"
  echo "MinIO Admin User: $MINIO_USER"
  echo "MinIO Admin Password: $MINIO_PASS"
} >>~/maxun.creds
cat <<EOF >/etc/default/minio
MINIO_ROOT_USER=${MINIO_USER}
MINIO_ROOT_PASSWORD=${MINIO_PASS}
EOF
systemctl enable -q --now minio
msg_ok "Setup MinIO"

msg_info "Installing Maxun (Patience)"
fetch_and_deploy_gh_release "maxun" "getmaxun/maxun" "source"
cat <<EOF >/opt/maxun/.env
NODE_ENV=development
JWT_SECRET=${JWT_SECRET}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}
DB_HOST=localhost
DB_PORT=5432
ENCRYPTION_KEY=${ENCRYPTION_KEY}
MINIO_ENDPOINT=localhost
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ACCESS_KEY=${MINIO_USER}
MINIO_SECRET_KEY=${MINIO_PASS}
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

BACKEND_PORT=8080
FRONTEND_PORT=5173
BACKEND_URL=http://${LOCAL_IP}:8080
PUBLIC_URL=http://${LOCAL_IP}:5173
VITE_BACKEND_URL=http://${LOCAL_IP}:8080
VITE_PUBLIC_URL=http://${LOCAL_IP}:5173

MAXUN_TELEMETRY=false
EOF

cat <<'EOF' >/usr/local/bin/update-env-ip.sh
env_file="/opt/maxun/.env"

sed -i "s|^BACKEND_URL=.*|BACKEND_URL=http://${LOCAL_IP}:8080|" "$env_file"
sed -i "s|^PUBLIC_URL=.*|PUBLIC_URL=http://${LOCAL_IP}:5173|" "$env_file"
sed -i "s|^VITE_BACKEND_URL=.*|VITE_BACKEND_URL=http://${LOCAL_IP}:8080|" "$env_file"
sed -i "s|^VITE_PUBLIC_URL=.*|VITE_PUBLIC_URL=http://${LOCAL_IP}:5173|" "$env_file"
EOF
chmod +x /usr/local/bin/update-env-ip.sh
cd /opt/maxun
$STD npm install
cd /opt/maxun/maxun-core
$STD npm install
cd /opt/maxun
$STD npx playwright install --with-deps chromium
$STD npx playwright install-deps
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed Maxun"

msg_info "Setting up nginx with CORS Proxy"
cat <<'EOF' >/etc/nginx/sites-available/maxun
server {
    listen 80;

    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }

    location ~ ^/(api|record|workflow|storage|auth|integration|proxy|api-docs) {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_http_version 1.1;

        add_header Access-Control-Allow-Origin "$http_origin" always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods GET,POST,PUT,DELETE,OPTIONS always;
        add_header Access-Control-Allow-Headers Authorization,Content-Type,X-Requested-With always;

        if ($request_method = OPTIONS) {
            return 204;
        }

        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;

        proxy_intercept_errors on;
        error_page 502 503 504 /50x.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/maxun /etc/nginx/sites-enabled/maxun
rm -f /etc/nginx/sites-enabled/default
msg_ok "nginx with CORS Proxy set up"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/maxun-update-env.service
[Unit]
Description=Update .env with dynamic LXC IP
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-env-ip.sh

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/maxun.service
[Unit]
Description=Maxun Service
After=network.target postgresql.service redis.service minio.service maxun-update-env.service

[Service]
WorkingDirectory=/opt/maxun
ExecStart=/usr/bin/npm run start
Restart=always
EnvironmentFile=/opt/maxun/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now maxun-update-env
systemctl enable -q --now maxun
systemctl enable -q --now nginx
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/v${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
