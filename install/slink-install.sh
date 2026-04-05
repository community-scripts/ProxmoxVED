#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/andrii-kryvoviaz/slink

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  caddy \
  redis-server \
  git
msg_ok "Installed Dependencies"

PHP_VERSION="8.5" PHP_FPM="YES" setup_php

setup_composer

NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs

fetch_and_deploy_gh_release "slink" "andrii-kryvoviaz/slink" "tarball"

msg_info "Building Client"
cd /opt/slink/services/client
$STD yarn install --frozen-lockfile --non-interactive
$STD yarn svelte-kit sync
NODE_OPTIONS="--max-old-space-size=2048" $STD yarn build
msg_ok "Built Client"

msg_info "Setting up API"
cd /opt/slink/services/api
[[ -f .env.example ]] && cp .env.example .env
APP_SECRET=$(openssl rand -hex 16)
ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c12)
JWT_PASS=$(openssl rand -hex 16)
{
  echo ""
  echo "APP_ENV=prod"
  echo "APP_SECRET=${APP_SECRET}"
} >>".env"
sed -i "s|^ADMIN_EMAIL=.*|ADMIN_EMAIL=admin@localhost|" .env
sed -i "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${ADMIN_PASS}|" .env
sed -i "s|^JWT_PASSPHRASE=.*|JWT_PASSPHRASE=${JWT_PASS}|" .env
sed -i "s|^CORS_ALLOW_ORIGIN=.*|CORS_ALLOW_ORIGIN='^https?://.*\$'|" .env
sed -i "s|sqlite:////app/var/data|sqlite:////opt/slink/services/api/var/data|g" .env
export APP_ENV=prod
mkdir -p /opt/slink/services/api/var/data
mkdir -p /opt/slink/services/api/config/jwt
openssl genpkey -algorithm RSA -out /opt/slink/services/api/config/jwt/private.pem -aes256 -pass "pass:${JWT_PASS}" 2>/dev/null
openssl pkey -in /opt/slink/services/api/config/jwt/private.pem -out /opt/slink/services/api/config/jwt/public.pem -pubout -passin "pass:${JWT_PASS}" 2>/dev/null
$STD composer install --no-dev --optimize-autoloader --no-interaction
mkdir -p /opt/slink/{data,images}
php bin/console lexik:jwt:generate-keypair --skip-if-exists >/dev/null 2>&1 || true
php bin/console doctrine:migrations:migrate --no-interaction >/dev/null 2>&1 || true
php bin/console cache:warm --no-optional-warmers >/dev/null 2>&1 || true
msg_ok "Set up API"

msg_info "Configuring Caddy"
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
cat <<EOF >/etc/caddy/Caddyfile
:8080 {
    root * /opt/slink/services/api/public
    php_fastcgi unix//run/php/php${PHP_VER}-fpm.sock
    file_server
    encode gzip
}
EOF
msg_ok "Configured Caddy"

msg_info "Creating Services"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
cat <<EOF >/etc/default/slink-client
PORT=3000
NODE_ENV=production
BODY_SIZE_LIMIT=Infinity
ORIGIN=http://${LOCAL_IP}:3000
EOF
cat <<'EOF' >/etc/systemd/system/slink-client.service
[Unit]
Description=Slink Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/slink/services/client
ExecStart=/usr/bin/node build/index.js
EnvironmentFile=/etc/default/slink-client
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server php${PHP_VER}-fpm caddy slink-client
{
  echo "Slink Credentials"
  echo "Admin Email: admin@localhost"
  echo "Admin Password: ${ADMIN_PASS}"
} >>~/slink.creds
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
