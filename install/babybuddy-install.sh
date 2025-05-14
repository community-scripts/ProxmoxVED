#!/usr/bin/env bash

# Copyright (c) 2021-2024 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | htt
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
  uwsgi \
  uwsgi-plugin-python3 \
  libopenjp2-7-dev \
  libpq-dev \
  nginx \
  python3 \
  python3-venv \
  python3-pip
msg_ok "Installed Dependencies"

msg_info "Installing Babybuddy"
cd /opt
RELEASE=$(curl -fsSL https://api.github.com/repos/babybuddy/babybuddy/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
wget -q "https://github.com/babybuddy/babybuddy/archive/refs/tags/v${RELEASE}.zip"
unzip -q v${RELEASE}.zip
mv babybuddy-${RELEASE} /opt/babybuddy
rm "v${RELEASE}.zip"
cd /opt/babybuddy
$STD pip install -U pip wheel pipenv
export PIPENV_VENV_IN_PROJECT=1
export PIPENV_IGNORE_VIRTUALENVS=1
export PIPENV_VERBOSITY=-1
$STD pipenv install
#$STD pipenv shell
cp babybuddy/settings/production.example.py babybuddy/settings/production.py
touch /opt/babybuddy/data/db.sqlite3
chown -R www-data:www-data /opt/babybuddy/data
chmod 640 /opt/babybuddy/data/db.sqlite3
chmod 750 /opt/babybuddy/data

SECRET_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
ALLOWED_HOSTS=$(hostname -I | tr ' ' ',' | sed 's/,$//')",127.0.0.1,localhost"
sed -i \
  -e "s/^SECRET_KEY = \"\"/SECRET_KEY = \"$SECRET_KEY\"/" \
  -e "s/^ALLOWED_HOSTS = \[\"\"\]/ALLOWED_HOSTS = \[$(echo \"$ALLOWED_HOSTS\" | sed 's/,/\",\"/g')\]/" \
  babybuddy/settings/production.py

export DJANGO_SETTINGS_MODULE=babybuddy.settings.production
python manage.py migrate

# Berechtigungen setzen
chown -R www-data:www-data /opt/babybuddy/data
chmod 640 /opt/babybuddy/data/db.sqlite3
chmod 750 /opt/babybuddy/data
msg_ok "Installed BabyBuddy WebApp"

# Django Admin Setup
DJANGO_ADMIN_USER=admin
DJANGO_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
python manage.py shell <<EOF
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='$DJANGO_ADMIN_USER').exists():
    u = User.objects.create_user('$DJANGO_ADMIN_USER', password='$DJANGO_ADMIN_PASS')
    u.is_superuser = True
    u.is_staff = True
    u.save()
EOF

{
  echo ""
  echo "Django-Credentials"
  echo "Django Admin User: $DJANGO_ADMIN_USER"
  echo "Django Admin Password: $DJANGO_ADMIN_PASS"
} >>~/babybuddy.creds
msg_ok "Setup Django Admin"

# uWSGI konfigurieren
msg_info "Configuring uWSGI"
sudo bash -c "cat > /etc/uwsgi/apps-available/babybuddy.ini" <<EOF
[uwsgi]
plugins = python3
project = babybuddy
base_dir = /opt/babybuddy
chdir = %(base_dir)
virtualenv = %(base_dir)/.venv
module = %(project).wsgi:application
env = DJANGO_SETTINGS_MODULE=%(project).settings.production
master = True
vacuum = True
EOF

sudo ln -sf /etc/uwsgi/apps-available/babybuddy.ini /etc/uwsgi/apps-enabled/babybuddy.ini
sudo service uwsgi restart

# NGINX konfigurieren
msg_info "Configuring NGINX"
cat <<EOF >/etc/nginx/sites-available/babybuddy
upstream babybuddy {
    server unix:///var/run/uwsgi/app/babybuddy/socket;
}

server {
    listen 80;
    server_name _;

    location / {
        uwsgi_pass babybuddy;
        include uwsgi_params;
    }

    location /media {
        alias /opt/babybuddy/media;
    }
}
EOF

ln -sf /etc/nginx/sites-available/babybuddy /etc/nginx/sites-enabled/babybuddy
service nginx restart

# Bereinigung
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
