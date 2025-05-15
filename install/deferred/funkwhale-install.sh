#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Python3"
$STD apt-get install -y --no-install-recommends \
  python3 \
  python3-dev \
  python3-setuptools \
  python3-venv 
msg_ok "Installed Python3"

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y --no-install-recommends \
  redis \
  postgresql \
  postgresql-contrib \
  postgresql-client \
  build-essential \
  gnupg \
  ffmpeg \
  libjpeg-dev \
  libpq-dev \
  libmagic-dev \
  libzbar0 \
  poppler-utils \
  automake \
  libtool \
  pkg-config \
  curl \
  libtiff-dev \
  libpng-dev \
  libleptonica-dev \
  sudo \
  make \
  mc
msg_ok "Installed Dependencies"

msg_info "Setup Funkwhale Dependencies (Patience)"
export FUNKWHALE_VERSION=1.4.0
$STD sudo apt install -y --no-install-recommends $(curl https://dev.funkwhale.audio/funkwhale/funkwhale/-/raw/$FUNKWHALE_VERSION/deploy/requirements.apt)
$STD sudo useradd --system --shell /bin/bash --create-home --home-dir /opt/funkwhale funkwhale
cd /opt/funkwhale
$STD sudo mkdir -p config api data/static data/media data/music front
$STD sudo chown -R funkwhale:funkwhale data
msg_ok "Initial Setup complete"

msg_ok "Download Funkwhale API"
$STD sudo curl -L -o "api-$FUNKWHALE_VERSION.zip" "https://dev.funkwhale.audio/funkwhale/funkwhale/-/jobs/artifacts/$FUNKWHALE_VERSION/download?job=build_api"
$STD sudo unzip -q "api-$FUNKWHALE_VERSION.zip" -d extracted
$STD sudo mv extracted/api/* api/
$STD sudo rm -rf extracted api-$FUNKWHALE_VERSION.zip
msg_ok "Downloaded and extracted Funkwhale API"

msg_info "Download Funkwhale Frontend"
$STD sudo curl -L -o "front-$FUNKWHALE_VERSION.zip" "https://dev.funkwhale.audio/funkwhale/funkwhale/-/jobs/artifacts/$FUNKWHALE_VERSION/download?job=build_front"
$STD sudo unzip -q "front-$FUNKWHALE_VERSION.zip" -d extracted
$STD sudo mv extracted/front .
$STD sudo rm -rf extracted front-$FUNKWHALE_VERSION.zip
msg_ok "Downloaded and extracted Funkwhale Frontend"

msg_info "Install Funkwhale API and DJANGO"
cd /opt/funkwhale
$STD sudo python3 -m venv venv
$STD sudo venv/bin/pip install --upgrade pip wheel
$STD sudo venv/bin/pip install --editable ./api
$STD sudo curl -L -o /opt/funkwhale/config/.env "https://dev.funkwhale.audio/funkwhale/funkwhale/raw/$FUNKWHALE_VERSION/deploy/env.prod.sample"
secret_key=$(openssl rand -base64 45 | sed 's/\//\\\//g')
sudo sed -i "s/DJANGO_SECRET_KEY=.*/DJANGO_SECRET_KEY=$secret_key/" /opt/funkwhale/config/.env
sudo sed -i 's/# CACHE_URL=redis:\/\/127.0.0.1:6379\/0/CACHE_URL=redis:\/\/127.0.0.1:6379\/0/' /opt/funkwhale/config/.env #Remove #Hashtag From Config for Debian
sudo sed -i 's/# DATABASE_URL=postgresql:\/\/funkwhale@:5432\/funkwhale/DATABASE_URL=postgresql:\/\/funkwhale@:5432\/funkwhale/' /opt/funkwhale/config/.env #Remove #Hashtag From Config for Debian
# set the paths to /opt instead of /srv
sudo sed -i 's/MEDIA_ROOT=\/srv\/funkwhale\/data\/media/MEDIA_ROOT=\/opt\/funkwhale\/data\/media/' /opt/funkwhale/config/.env
sudo sed -i 's/STATIC_ROOT=\/srv\/funkwhale\/data\/static/STATIC_ROOT=\/opt\/funkwhale\/data\/static/' /opt/funkwhale/config/.env
sudo sed -i 's/MUSIC_DIRECTORY_PATH=\/srv\/funkwhale\/data\/music/MUSIC_DIRECTORY_PATH=\/opt\/funkwhale\/data\/music/' /opt/funkwhale/config/.env
sudo sed -i 's/MUSIC_DIRECTORY_SERVE_PATH=\/srv\/funkwhale\/data\/music/MUSIC_DIRECTORY_SERVE_PATH=\/opt\/funkwhale\/data\/music/' /opt/funkwhale/config/.env
sudo sed -i 's/FUNKWHALE_FRONTEND_PATH=\/srv\/funkwhale\/front\/dist/FUNKWHALE_FRONTEND_PATH=\/opt\/funkwhale\/front\/dist/' /opt/funkwhale/config/.env
sudo chown funkwhale:funkwhale /opt/funkwhale/config/.env
sudo chmod 600 /opt/funkwhale/config/.env
msg_ok "Environment successfully set up"

msg_info "Setting up Database"
DB_NAME=funkwhale
DB_USER=funkwhale
DB_EXTENSION_UNACCENT=unaccent
DB_EXTENSION_CITEXT=citext
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
SECRET_KEY="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE template0;"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 
echo "" >>~/funkwhale.creds
echo -e "Funkwhale Database User: \e[32m$DB_USER\e[0m" >>~/funkwhale.creds
echo -e "Funkwhale Database Password: \e[32m$DB_PASS\e[0m" >>~/funkwhale.creds
echo -e "Funkwhale Database Name: \e[32m$DB_NAME\e[0m" >>~/funkwhale.creds
$STD sudo -u postgres psql -c "CREATE EXTENSION $DB_EXTENSION_UNACCENT;"
$STD sudo -u postgres psql -c "CREATE EXTENSION $DB_EXTENSION_CITEXT;"
cd /opt/funkwhale
$STD sudo -u funkwhale venv/bin/funkwhale-manage migrate
msg_ok "Set up PostgreSQL database"

msg_info "Setting up Funkwhale and systemd"
FUNKWHALE_USER=funkwhale_su
FUNKWHALE_MAIL=mail@example.com
FUNKWHALE_PASS="$(openssl rand -base64 18 | cut -c1-13)"
echo -e "Funkwhale Superuser: \e[32m$FUNKWHALE_USER\e[0m" >>~/funkwhale.creds
echo -e "Funkwhale Mail: \e[32m$FUNKWHALE_MAIL\e[0m" >>~/funkwhale.creds
echo -e "Funkwhale Superuser Password: \e[32m$FUNKWHALE_PASS\e[0m" >>~/funkwhale.creds
$STD sudo -u funkwhale venv/bin/funkwhale-manage fw users create --superuser --username $FUNKWHALE_USER --email $FUNKWHALE_MAIL --password $FUNKWHALE_PASS
$STD sudo venv/bin/funkwhale-manage collectstatic
$STD sudo curl -L -o "/etc/systemd/system/funkwhale.target" "https://dev.funkwhale.audio/funkwhale/funkwhale/raw/$FUNKWHALE_VERSION/deploy/funkwhale.target"
$STD sudo curl -L -o "/etc/systemd/system/funkwhale-server.service" "https://dev.funkwhale.audio/funkwhale/funkwhale/raw/$FUNKWHALE_VERSION/deploy/funkwhale-server.service"
$STD sudo curl -L -o "/etc/systemd/system/funkwhale-worker.service" "https://dev.funkwhale.audio/funkwhale/funkwhale/raw/$FUNKWHALE_VERSION/deploy/funkwhale-worker.service"
$STD sudo curl -L -o "/etc/systemd/system/funkwhale-beat.service" "https://dev.funkwhale.audio/funkwhale/funkwhale/raw/$FUNKWHALE_VERSION/deploy/funkwhale-beat.service"
$STD sudo systemctl daemon-reload
$STD sudo systemctl start funkwhale.target
$STD sudo systemctl enable --now funkwhale.target
msg_ok "Funkwhale successfully set up"

read -r -p "Would you like to Setup Reverse Proxy (Nginx)? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  msg_info "Installing NGINX"
  $STD apt install -y nginx
  sudo su
  $STD curl -L -o /etc/nginx/funkwhale_proxy.conf "https://dev.funkwhale.audio/funkwhale/funkwhale/raw/$FUNKWHALE_VERSION/deploy/funkwhale_proxy.conf"
  $STD curl -L -o /etc/nginx/sites-available/funkwhale.template "https://dev.funkwhale.audio/funkwhale/funkwhale/raw/$FUNKWHALE_VERSION/deploy/nginx.template"
  $STD set -a && source /opt/funkwhale/config/.env && set +a envsubst "`env | awk -F = '{printf \" $%s\", $$1}'`" \
   < /etc/nginx/sites-available/funkwhale.template \
   > /etc/nginx/sites-available/funkwhale.conf
  $STD grep '${' /etc/nginx/sites-available/funkwhale.conf
  $STD ln -s /etc/nginx/sites-available/funkwhale.conf /etc/nginx/sites-enabled/
  $STD systemctl reload nginx
  msg_ok "Installed Nginx"
fi

read -r -p "Would you like to Setup TLS (Certbot)? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  msg_info "Installing Certbot"
  $STD apt install -y certbot python3-certbot-nginx
  $STD sudo certbot --nginx -d $FUNKWHALE_HOSTNAME
  msg_ok "Installed Certbot"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
