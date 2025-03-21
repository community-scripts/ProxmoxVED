#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
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
  gnupg2\
  postgresql \
  lsb-release \
  rbenv \
  libpq-dev \
  libarchive-dev \
  git \
  libmariadb-dev \
  redis-server \
  nginx
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
} >> ~/manyfold.creds
msg_ok "Set up PostgreSQL"

msg_info "Setting up Node.js/Yarn"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
$STD npm install -g npm@latest
$STD npm install -g yarn
msg_ok "Installed Node.js/Yarn"

msg_info "Installing Ruby Version Manager"
$STD gpg2 --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
curl -sSL https://get.rvm.io -o install_rvm.sh
chmod +x install_rvm.sh
bash install_rvm.sh stable
msg_ok "Installed Ruby Version Manager"

msg_info "Adding manyfold user"
useradd -m -s /usr/bin/bash manyfold
usermod -a -G rvm manyfold
msg_ok "Added manyfold user"

msg_info "Installing Manyfold"
RELEASE=$(curl -s https://api.github.com/repos/manyfold3d/manyfold/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
cd /opt
wget -q "https://github.com/manyfold3d/manyfold/archive/refs/tags/v${RELEASE}.zip"
unzip -q "v${RELEASE}.zip"
mv /opt/manyfold-${RELEASE}/ /opt/manyfold
cd /opt/manyfold
chown -R manyfold:manyfold /opt/manyfold
RUBY_VERSION=$(cat .ruby-version)
YARN_VERSION=$(grep '"packageManager":' package.json | sed -E 's/.*"(yarn@[0-9\.]+)".*/\1/')
$STD gem install bundler
/bin/bash --login -c "rvm install $RUBY_VERSION"
/bin/bash --login -c "rvm use --default $RUBY_VERSION"
$STD bundle install #do not run as root
$STD gem install sidekiq
$STD npm install --global corepack
corepack enable
$STD corepack prepare $YARN_VERSION --activate
$STD corepack use $YARN_VERSION --global
$STD yarn install
cat <<EOF >/opt/.env
APP_VERSION=${RELEASE}
GUID=1002
PUID=1001
PUBLIC_HOSTNAME=subdomain.somehost.org
PUBLIC_PORT=5000
SECRET_KEY_BASE=$(bundle exec rails secret)
REDIS_URL=redis://127.0.0.1:6379/1
DATABASE_ADAPTER=postgresql
DATABASE_HOST=127.0.0.1
DATABASE_USER=${DB_USER}
DATABASE_PASSWORD=${DB_PASS}
DATABASE_NAME=${DB_NAME}
DATABASE_CONNECTION_POOL=16
MULTIUSER=enabled
HTTPS_ONLY=false
RAILS_ENV=production
EOF
chown manyfold:manyfold /opt/.env
source /opt/.env && bin/rails db:migrate
source /opt/.env && bin/rails assets:precompile
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed manyfold"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/manyfold.service
[Unit]
Description=Manyfold3d
Requires=network.target

[Service]
Type=simple
User=manyfold
Group=manyfold
WorkingDirectory=/opt/manyfold
EnvironmentFile=/opt/.env
ExecStart=/usr/bin/bash -lc '/opt/manyfold/bin/rails server -b 127.0.0.1 --port 5000 --environment production'
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
rm -rf "/opt/v${RELEASE}.zip"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
