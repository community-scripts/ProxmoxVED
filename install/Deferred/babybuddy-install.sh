#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck
# Co-Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE
# Source: https://github.com/AnalogJ/scrutiny

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installiere benötigte Pakete
msg_info "Installing Dependencies"
$STD apt-get install -y \
  sudo \
  curl \
  uwsgi \
  uwsgi-plugin-python3 \
  libopenjp2-7-dev \
  libpq-dev \
  git \
  nginx \
  python3 \
  python3-pip \
  python3-venv \
  pipx
msg_ok "Installed Dependencies"

# Installiere Python3 und PipX
#msg_info "Installing Python3 & PipX" 
#$STD apt-get install -y python3 python3-dev python3-dotenv python3-pip 

#source /opt/babybuddy/.venv/bin/activate
#msg_ok "Installed Python3 & PipX"

# Variablen
INSTALL_DIR="/opt/babybuddy"
APP_DIR="$INSTALL_DIR"
DATA_DIR="$INSTALL_DIR/data"
DOMAIN="babybuddy.example.com"  # Ändern, falls benötigt
SECRET_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)

# Babybuddy Repository installieren
msg_info "Installing Babybuddy"
cd /opt
RELEASE=$(curl -s https://api.github.com/repos/babybuddy/babybuddy/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
wget -q "https://github.com/babybuddy/babybuddy/archive/refs/tags/v${RELEASE}.zip"
unzip -q v${RELEASE}.zip
mv babybuddy-${RELEASE} /opt/babybuddy
cd /opt/babybuddy
source /opt/babybuddy/.venv/bin/activate
export PIPENV_VENV_IN_PROJECT=1
pipenv install
pipenv shell
cp babybuddy/settings/production.example.py babybuddy/settings/production.py

# Production-Settings konfigurieren
SECRET_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
ALLOWED_HOSTS=$(hostname -I | tr ' ' ',' | sed 's/,$//')",127.0.0.1,localhost"
sed -i \
    -e "s/^SECRET_KEY = \"\"/SECRET_KEY = \"$SECRET_KEY\"/" \
    -e "s/^ALLOWED_HOSTS = \[\"\"\]/ALLOWED_HOSTS = \[$(echo \"$ALLOWED_HOSTS\" | sed 's/,/\",\"/g')\]/" \
    babybuddy/settings/production.py

# Django Migrationen durchführen
export DJANGO_SETTINGS_MODULE=babybuddy.settings.production
python manage.py migrate

# Berechtigungen setzen
sudo chown -R www-data:www-data /opt/babybuddy/data
sudo chmod 640 /opt/babybuddy/data/db.sqlite3
sudo chmod 750 /opt/babybuddy/data
msg_ok "Installed BabyBuddy WebApp"

# Django Admin Setup
DJANGO_ADMIN_USER=admin
DJANGO_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
source /opt/babybuddy/bin/activate
$STD python3 /opt/babybuddy/manage.py shell << EOF
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('$DJANGO_ADMIN_USER', password='$DJANGO_ADMIN_PASS')
user.is_superuser = True
user.is_staff = True
user.save()
EOF

{
    echo ""
    echo "Django-Credentials"
    echo "Django Admin User: $DJANGO_ADMIN_USER"
    echo "Django Admin Password: $DJANGO_ADMIN_PASS"
} >> ~/babybuddy.creds
msg_ok "Setup Django Admin"

# uWSGI konfigurieren
msg_info "Configuring uWSGI"
sudo bash -c "cat > /etc/uwsgi/apps-available/babybuddy.ini" <<EOF
[uwsgi]
plugins = python3
project = babybuddy
base_dir = $INSTALL_DIR
chdir = %(base_dir)/public
virtualenv = %(chdir)/.venv
module = %(project).wsgi:application
env = DJANGO_SETTINGS_MODULE=%(project).settings.production
master = True
vacuum = True
EOF

sudo ln -sf /etc/uwsgi/apps-available/babybuddy.ini /etc/uwsgi/apps-enabled/babybuddy.ini
sudo service uwsgi restart

# NGINX konfigurieren
msg_info "Configuring NGINX"
sudo bash -c "cat > /etc/nginx/sites-available/babybuddy" <<EOF
upstream babybuddy {
 server unix:///var/run/uwsgi/app/babybuddy/socket;
}

server {
 listen 80;
 server_name $DOMAIN;

 location / {
    uwsgi_pass babybuddy;
    include uwsgi_params;
 }
 
 location /media {
    alias $DATA_DIR/media;
 }
}
EOF

sudo ln -sf /etc/nginx/sites-available/babybuddy /etc/nginx/sites-enabled/babybuddy
sudo service nginx restart

# Abschlussnachricht
echo "Deployment abgeschlossen! Besuche http://$DOMAIN"

# Bereinigung
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
