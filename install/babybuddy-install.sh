#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | http
# Source: https://github.com/babybuddy/babybuddy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  uwsgi \
  uwsgi-plugin-python3 \
  libopenjp2-7-dev \
  libpq-dev \
  nginx \
  python3
msg_ok "Installed Dependencies"

setup_uv

msg_info "Installing Babybuddy"
RELEASE=$(curl -fsSL https://api.github.com/repos/babybuddy/babybuddy/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
temp_file=$(mktemp)
mkdir -p /opt/{babybuddy,data}
curl -fsSL "https://github.com/babybuddy/babybuddy/archive/refs/tags/v${RELEASE}.tar.gz" -o "$temp_file"
tar zxf "$temp_file" --strip-components=1 -C /opt/babybuddy
cd /opt/babybuddy
$STD uv venv .venv
$STD source .venv/bin/activate
$STD uv pip install -r requirements.txt
cp babybuddy/settings/production.example.py babybuddy/settings/production.py
SECRET_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
ALLOWED_HOSTS=$(hostname -I | tr ' ' ',' | sed 's/,$//')",127.0.0.1,localhost"
sed -i \
  -e "s/^SECRET_KEY = \"\"/SECRET_KEY = \"$SECRET_KEY\"/" \
  -e "s/^ALLOWED_HOSTS = \[\"\"\]/ALLOWED_HOSTS = \[$(echo \"$ALLOWED_HOSTS\" | sed 's/,/\",\"/g')\]/" \
  babybuddy/settings/production.py

export DJANGO_SETTINGS_MODULE=babybuddy.settings.production
python manage.py migrate
chown -R www-data:www-data /opt/data
chmod 640 /opt/data/db.sqlite3
chmod 750 /opt/data

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

msg_info "Configuring uWSGI"
cat <<EOF >/etc/uwsgi/apps-available/babybuddy.ini
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
socket = /var/run/uwsgi/app/babybuddy/socket
chmod-socket = 660
uid = www-data
gid = www-data
EOF
ln -sf /etc/uwsgi/apps-available/babybuddy.ini /etc/uwsgi/apps-enabled/babybuddy.ini
service uwsgi restart
msg_ok "Configured uWSGI"

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
rm /etc/nginx/sites-enabled/default
systemctl enable -q --now nginx
msg_ok "Configured NGINX"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
