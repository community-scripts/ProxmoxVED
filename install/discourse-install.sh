#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.discourse.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  libyaml-dev \
  curl \
  git \
  imagemagick \
  gsfonts \
  brotli \
  nginx \
  redis-server
msg_ok "Installed Dependencies"

PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
NODE_VERSION="22" setup_nodejs
RUBY_VERSION="3.4.4" setup_ruby

msg_info "Configuring PostgreSQL for Discourse"
DISCOURSE_DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
PG_HBA="/etc/postgresql/16/main/pg_hba.conf"
sed -i 's/^local\s\+all\s\+all\s\+peer$/local   all             all                                     md5/' "$PG_HBA"
$STD systemctl restart postgresql
PG_DB_NAME="discourse" PG_DB_USER="discourse" PG_DB_PASS="$DISCOURSE_DB_PASS" setup_postgresql_db
msg_ok "Configured PostgreSQL for Discourse"

msg_info "Configuring Discourse"
DISCOURSE_SECRET_KEY=$(openssl rand -hex 64)
$STD git clone --depth 1 https://github.com/discourse/discourse.git /opt/discourse
cd /opt/discourse
cat <<EOF >/opt/discourse/.env
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
SECRET_KEY_BASE=${DISCOURSE_SECRET_KEY}
DISCOURSE_DB_HOST=/var/run/postgresql
DISCOURSE_DB_PORT=5432
DISCOURSE_DB_NAME=discourse
DISCOURSE_DB_USERNAME=discourse
DISCOURSE_DB_PASSWORD=${DISCOURSE_DB_PASS}
DISCOURSE_REDIS_URL=redis://localhost:6379
DISCOURSE_DEVELOPER_EMAILS=admin@local
DISCOURSE_HOSTNAME=${LOCAL_IP}
DISCOURSE_SMTP_ADDRESS=localhost
DISCOURSE_SMTP_PORT=25
DISCOURSE_SMTP_AUTHENTICATION=none
DISCOURSE_NOTIFICATION_EMAIL=noreply@${LOCAL_IP}
EOF

chown -R root:root /opt/discourse
chmod 755 /opt/discourse
msg_ok "Configured Discourse"

msg_info "Installing Discourse Dependencies"
$STD systemctl enable --now redis-server
cd /opt/discourse
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init - bash)" 2>/dev/null || true
export RAILS_ENV=production
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack enable
$STD bundle config set --local deployment true
$STD bundle config set --local without 'test development'
$STD bundle install
$STD pnpm install
msg_ok "Installed Discourse Dependencies"

msg_info "Setting Up Database"
cd /opt/discourse
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init - bash)" 2>/dev/null || true
export RAILS_ENV=production
set -a
source /opt/discourse/.env
set +a
$STD runuser -u postgres -- psql -d discourse -c "CREATE EXTENSION IF NOT EXISTS vector;"
$STD bundle exec rails db:migrate
msg_ok "Set Up Database"

msg_info "Building Discourse Assets"
cd /opt/discourse
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init - bash)" 2>/dev/null || true
export RAILS_ENV=production
set -a
source /opt/discourse/.env
set +a
$STD bundle exec rails assets:precompile
msg_ok "Built Discourse Assets"

msg_info "Preparing Admin Onboarding"
msg_ok "Automatic admin bootstrap skipped (use first signup in UI with admin@local)"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/discourse.service
[Unit]
Description=Discourse Forum
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/discourse
Environment=RAILS_ENV=production
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/root/.rbenv/shims/bundle exec puma -w 2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now discourse
msg_ok "Created Service"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/discourse
server {
  listen 80 default_server;
  server_name _;
  
  client_max_body_size 100M;
  proxy_busy_buffers_size 512k;
  proxy_buffers 4 512k;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

ln -sf /etc/nginx/sites-available/discourse /etc/nginx/sites-enabled/discourse
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
$STD systemctl enable --now nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
