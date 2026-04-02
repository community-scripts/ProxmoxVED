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

PHP_VERSION="8.5" setup_php

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
sed -i "s|^APP_SECRET=.*|APP_SECRET=${APP_SECRET}|" .env
sed -i "s|^APP_ENV=.*|APP_ENV=prod|" .env
export APP_ENV=prod
$STD composer install --no-dev --optimize-autoloader --no-interaction
mkdir -p /opt/slink/{data,images}
$STD php bin/console cache:warm --no-optional-warmers 2>/dev/null || true
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
cat <<EOF >/etc/systemd/system/slink-client.service
[Unit]
Description=Slink Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/slink/services/client
ExecStart=/usr/bin/node build/index.js
Environment=PORT=3000 NODE_ENV=production BODY_SIZE_LIMIT=Infinity
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server php${PHP_VER}-fpm caddy slink-client
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
