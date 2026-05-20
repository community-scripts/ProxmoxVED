#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/stoatchat/stoatchat

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  pkg-config \
  libssl-dev \
  build-essential \
  git \
  redis-server \
  rabbitmq-server \
  nginx
msg_ok "Installed Dependencies"

setup_mongodb

msg_info "Configuring RabbitMQ"
systemctl enable -q --now rabbitmq-server
until rabbitmqctl status &>/dev/null; do sleep 1; done
$STD rabbitmqctl add_user rabbituser rabbitpass
$STD rabbitmqctl set_permissions -p / rabbituser ".*" ".*" ".*"
msg_ok "Configured RabbitMQ"

setup_rust

fetch_and_deploy_gh_release "stoatchat" "stoatchat/stoatchat" "tarball"

msg_info "Building Backend (Patience)"
cd /opt/stoatchat
$STD cargo build --release --bins -j 2
msg_ok "Built Backend"

NODE_VERSION="22" setup_nodejs

msg_info "Installing pnpm"
$STD npm install -g pnpm@10.28.1
msg_ok "Installed pnpm"

msg_info "Cloning Web Frontend"
FORWEB_VERSION=$(get_latest_github_release "stoatchat/for-web")
$STD git clone --recursive "https://github.com/stoatchat/for-web" /opt/stoatchat-web
$STD git -C /opt/stoatchat-web checkout "$FORWEB_VERSION"
$STD git -C /opt/stoatchat-web submodule update --init --recursive
msg_ok "Cloned Web Frontend"

msg_info "Building Web Frontend"
cd /opt/stoatchat-web
$STD pnpm install --frozen-lockfile
$STD pnpm --filter stoat.js build
$STD pnpm --filter solid-livekit-components build
$STD pnpm --filter "@lingui-solid/babel-plugin-lingui-macro" build
$STD pnpm --filter "@lingui-solid/babel-plugin-extract-messages" build
$STD pnpm --filter client exec lingui compile --typescript
$STD pnpm --filter client exec node scripts/copyAssets.mjs
$STD pnpm --filter client exec panda codegen
VITE_API_URL="http://${LOCAL_IP}/api" \
  VITE_WS_URL="ws://${LOCAL_IP}/ws" \
  VITE_MEDIA_URL="http://${LOCAL_IP}/autumn" \
  VITE_PROXY_URL="http://${LOCAL_IP}/january" \
  $STD pnpm --filter client exec vite build
msg_ok "Built Web Frontend"

fetch_and_deploy_gh_release "minio" "minio/minio" "singlefile" "latest" "/opt/stoatchat" "minio_linux_amd64"
mv /opt/stoatchat/minio_linux_amd64 /usr/local/bin/minio
chmod +x /usr/local/bin/minio

fetch_and_deploy_gh_release "mc" "minio/mc" "singlefile" "latest" "/opt/stoatchat" "mc_linux_amd64"
mv /opt/stoatchat/mc_linux_amd64 /usr/local/bin/mc
chmod +x /usr/local/bin/mc

msg_info "Configuring MinIO"
mkdir -p /opt/stoatchat/data/minio
cat <<EOF >/etc/systemd/system/stoatchat-minio.service
[Unit]
Description=Stoatchat MinIO Object Storage
After=network.target

[Service]
Type=simple
User=root
Environment=MINIO_ROOT_USER=minioautumn
Environment=MINIO_ROOT_PASSWORD=minioautumn
ExecStart=/usr/local/bin/minio server /opt/stoatchat/data/minio --console-address :9001
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now stoatchat-minio
msg_ok "Configured MinIO"

msg_info "Creating MinIO Bucket"
until mc alias set local http://127.0.0.1:9000 minioautumn minioautumn &>/dev/null; do sleep 1; done
$STD mc mb local/revolt-uploads
msg_ok "Created MinIO Bucket"

FILES_ENCRYPTION_KEY=$(openssl rand -base64 32)

msg_info "Creating Configuration"
cat <<EOF >/Revolt.toml
[database]
mongodb = "mongodb://127.0.0.1:27017"
redis = "redis://127.0.0.1:6379/"

[hosts]
app = "http://${LOCAL_IP}"
api = "http://${LOCAL_IP}/api"
events = "ws://${LOCAL_IP}/ws"
autumn = "http://${LOCAL_IP}/autumn"
january = "http://${LOCAL_IP}/january"

[rabbit]
host = "127.0.0.1"
port = 5672
username = "rabbituser"
password = "rabbitpass"

[files]
encryption_key = "${FILES_ENCRYPTION_KEY}"

[files.s3]
endpoint = "http://127.0.0.1:9000"
path_style_buckets = true
region = "minio"
access_key_id = "minioautumn"
secret_access_key = "minioautumn"
default_bucket = "revolt-uploads"

[api.registration]
invite_only = false
EOF
ln -sf /Revolt.toml /opt/stoatchat/Revolt.toml
msg_ok "Created Configuration"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/stoatchat
server {
    listen 80;

    client_max_body_size 20M;

    location /api {
        proxy_pass http://127.0.0.1:14702;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /ws {
        proxy_pass http://127.0.0.1:14703;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /autumn {
        proxy_pass http://127.0.0.1:14704;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /january {
        proxy_pass http://127.0.0.1:14705;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        root /opt/stoatchat-web/packages/client/dist;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
ln -sf /etc/nginx/sites-available/stoatchat /etc/nginx/sites-enabled/stoatchat
rm -f /etc/nginx/sites-enabled/default
systemctl enable -q --now nginx
msg_ok "Configured Nginx"

msg_info "Creating Backend Services"
for SVC in api events autumn january crond; do
  case $SVC in
  api)
    PORT=14702
    BIN=delta
    ;;
  events)
    PORT=14703
    BIN=bonfire
    ;;
  autumn)
    PORT=14704
    BIN=autumn
    ;;
  january)
    PORT=14705
    BIN=january
    ;;
  crond)
    PORT=0
    BIN=crond
    ;;
  esac
  cat <<EOF >/etc/systemd/system/stoatchat-${SVC}.service
[Unit]
Description=Stoatchat ${SVC} service
After=network.target stoatchat-minio.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/stoatchat
ExecStart=/opt/stoatchat/target/release/${BIN}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "stoatchat-${SVC}"
done
msg_ok "Created Backend Services"

motd_ssh
customize
cleanup_lxc
