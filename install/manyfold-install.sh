#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  gnupg2 postgresql \
  lsb-release \
  rbenv \
  libpq-dev \
  libarchive-dev \
  git \
  libmariadb-dev \
  redis-server \
  nginx \
  libffi-dev \
  libyaml-dev
msg_ok "Installed Dependencies"

msg_info "Setting up PostgreSQL"
DB_NAME=manyfold
DB_USER=manyfold
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE template0;"
{
  echo "Manyfold Credentials"
  echo "Manyfold Database User: $DB_USER"
  echo "Manyfold Database Password: $DB_PASS"
  echo "Manyfold Database Name: $DB_NAME"
} >>~/manyfold.creds
msg_ok "Set up PostgreSQL"

msg_info "Downloading Manyfold"
RELEASE=$(curl -fsSL https://api.github.com/repos/manyfold3d/manyfold/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
cd /opt
curl -fsSL "https://github.com/manyfold3d/manyfold/archive/refs/tags/v${RELEASE}.zip" -o manyfold.zip
unzip -q manyfold.zip
mv /opt/manyfold-${RELEASE}/ /opt/manyfold
RUBY_INSTALL_VERSION=$(cat /opt/manyfold/.ruby-version)
YARN_VERSION=$(grep '"packageManager":' /opt/manyfold/package.json | sed -E 's/.*"(yarn@[0-9\.]+)".*/\1/')

msg_ok "Downloaded Manyfold"

NODE_VERSION="22" NODE_MODULE="npm@latest,${YARN_VERSION}" install_node_and_modules
RUBY_VERSION=${RUBY_INSTALL_VERSION} RUBY_INSTALL_RAILS="true" setup_rbenv_stack

# msg_info "Add ruby-build"
# mkdir -p ~/.rbenv/plugins
# cd ~/.rbenv/plugins
# RUBY_BUILD_RELEASE=$(curl -s https://api.github.com/repos/rbenv/ruby-build/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
# curl -fsSL "https://github.com/rbenv/ruby-build/archive/refs/tags/v${RUBY_BUILD_RELEASE}.zip" -o ruby-build.zip
# unzip -q ruby-build.zip
# mv ruby-build-* ~/.rbenv/plugins/ruby-build
# echo "${RUBY_BUILD_RELEASE}" >~/.rbenv/plugins/RUBY_BUILD_version.txt
# msg_ok "Added ruby-build"

# msg_info "Installing ruby ${RUBY_VERSION}"
# $STD rbenv install $RUBY_VERSION
# echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >>~/.bashrc
# echo 'eval "$(rbenv init -)"' >>~/.bashrc
# source ~/.bashrc
# msg_ok "Installed ruby ${RUBY_VERSION}"

msg_info "Adding manyfold user"
useradd -m -s /usr/bin/bash manyfold
msg_ok "Added manyfold user"

msg_info "Setting .env file"
cat <<EOF >/opt/.env
export APP_VERSION=${RELEASE}
export GUID=1002
export PUID=1001
export PUBLIC_HOSTNAME=subdomain.somehost.org
export PUBLIC_PORT=5000
export REDIS_URL=redis://127.0.0.1:6379/1
export DATABASE_ADAPTER=postgresql
export DATABASE_HOST=127.0.0.1
export DATABASE_USER=${DB_USER}
export DATABASE_PASSWORD=${DB_PASS}
export DATABASE_NAME=${DB_NAME}
export DATABASE_CONNECTION_POOL=16
export MULTIUSER=enabled
export HTTPS_ONLY=false
export RAILS_ENV=production
EOF
msg_ok ".env file setup"

msg_info "Installing Manyfold"
source /opt/.env
cd /opt/manyfold
chown -R manyfold:manyfold /opt/manyfold
$STD gem install bundler
$STD rbenv global $RUBY_INSTALL_VERSION
$STD bundle install
$STD gem install sidekiq
$STD npm install --global corepack
corepack enable
$STD corepack prepare $YARN_VERSION --activate
$STD corepack use $YARN_VERSION
chown manyfold:manyfold /opt/.env
rm /opt/manyfold/config/credentials.yml.enc
$STD bin/rails credentials:edit
$STD bin/rails db:migrate
$STD bin/rails assets:precompile
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed manyfold"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/manyfold.service
[Unit]
Description=Manyfold3d
Requires=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/manyfold
ExecStart=/usr/bin/bash -lc 'source /opt/.env && /opt/manyfold/bin/rails server -b 127.0.0.1 --port 5000 --environment production'
TimeoutSec=30
RestartSec=15s
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now manyfold

cat <<EOF >/etc/nginx/sites-available/manyfold.conf
server {
    listen 80;
    server_name manyfold;
    root /opt/manyfold/public;

    location / {
        try_files \$uri/index.html \$uri @rails;
    }

    location @rails {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -s /etc/nginx/sites-available/manyfold.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf "/opt/manyfold.zip"
rm -rf "~/.rbenv/plugins/ruby-build.zip"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
