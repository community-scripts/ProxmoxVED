#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://maybefinance.com

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y --no-install-recommends \
  libpq-dev \
  libvips42 \
  git \
  zlib1g-dev \
  build-essential \
  libssl-dev \
  libreadline-dev \
  libyaml-dev \
  libsqlite3-dev \
  sqlite3 \
  libxml2-dev \
  libxslt1-dev \
  libcurl4-openssl-dev \
  software-properties-common \
  libffi-dev \
  redis
msg_ok "Installed Dependencies"

PG_VERSION=16 install_postgresql
RUBY_VERSION=3.4.1 RUBY_INSTALL_RAILS=false setup_rbenv_stack

msg_info "Setting up Postgresql"
DB_NAME="maybe"
DB_USER="maybe"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE template0;"
{
  echo "${APPLICATION} database credentials"
  echo "Database Name: ${DB_NAME}"
  echo "Database User: ${DB_USER}"
  echo "Database Password: ${DB_PASS}"
} >~/maybe.creds
msg_ok "Setup Postgresql"

msg_info "Installing ${APPLICATION}"
RELEASE=$(curl -s https://api.github.com/repos/maybe-finance/maybe/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
curl -fsSL "https://github.com/maybe-finance/maybe/archive/refs/tags/v${RELEASE}.zip" -o /tmp/v"$RELEASE".zip
unzip -q /tmp/v"$RELEASE".zip
mv maybe-"$RELEASE" /opt/maybe
cd /opt/maybe
cp ./.env.example ./.env
sed -i -e '/SELF_/a RAILS_ENV=production' \
  -e "s/secret-value/\"$(openssl rand -hex 64)\"/" \
  -e "/^SECRET_KEY/a RAILS_MASTER_KEY=\"$(openssl rand -hex 16)\"" \
  -e "s/_USER=postgres/_USER=${DB_USER}/" \
  -e "s/_PASSWORD=postgres/_PASSWORD=${DB_PASS}/" \
  -e "/_USER=/a POSTGRES_DB=${DB_NAME}" \
  -e 's/^# DISABLE/DISABLE/' \
  ./.env
sed -i -e '/_DB=/a\
\
REDIS_URL=redis://localhost:6379/1' \
  -e '/_SSL/a\
RAILS_FORCE_SSL=false\
RAILS_ASSUME_SSL=false' \
  ./.env
rm -f ./config/credentials.yml.enc
$STD ./bin/bundle install
$STD ./bin/bundle exec bootsnap precompile --gemfile -j 0
$STD ./bin/bundle exec bootsnap precompile -j 0 app/ lib/
export SECRET_KEY_BASE_DUMMY=1
$STD ./bin/rails assets:precompile
$STD dotenv -f ./.env ./bin/rails db:prepare
echo "${RELEASE}" >/opt/maybe_version.txt
msg_ok "Installed ${APPLICATION}"

msg_info "Creating services"

cat <<EOF >/etc/systemd/system/maybe-web.service
[Unit]
Description=${APPLICATION} Web Service
After=network.target redis.service postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/maybe
ExecStart=/root/.rbenv/shims/dotenv -f /opt/maybe/.env /opt/maybe/bin/rails s
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/maybe-worker.service
[Unit]
Description=${APPLICATION} Worker Service
After=redis.service

[Service]
Type=simple
WorkingDirectory=/opt/maybe
ExecStart=/root/.rbenv/shims/dotenv -f /opt/maybe/.env /opt/maybe/bin/bundle exec sidekiq
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now maybe-web maybe-worker
msg_ok "Created services"

motd_ssh
customize

msg_info "Cleaning up"
rm -f /tmp/v"$RELEASE".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
