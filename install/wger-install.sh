#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/wger-project/wger

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  apache2 \
  libapache2-mod-wsgi-py3 \
  libpq-dev
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="sass" setup_nodejs
setup_uv

PG_VERSION="16" setup_postgresql
PG_DB_NAME="wger" PG_DB_USER="wger" setup_postgresql_db

fetch_and_deploy_gh_release "wger" "wger-project/wger" "tarball" "latest" "/opt/wger"

msg_info "Setting up wger"
mkdir -p /opt/wger/{static,media}
chmod o+w /opt/wger/media
cd /opt/wger
$STD corepack enable
$STD npm install
$STD npm run build:css:sass
$STD uv venv
$STD uv pip install .
SECRET_KEY=$(openssl rand -base64 40)
cat <<EOF >/opt/wger/.env
DJANGO_DB_ENGINE=django.db.backends.postgresql
DJANGO_DB_DATABASE=${PG_DB_NAME}
DJANGO_DB_USER=${PG_DB_USER}
DJANGO_DB_PASSWORD=${PG_DB_PASS}
DJANGO_DB_HOST=localhost
DJANGO_DB_PORT=5432
DJANGO_MEDIA_ROOT=/opt/wger/media
DJANGO_STATIC_ROOT=/opt/wger/static
SECRET_KEY=${SECRET_KEY}
EOF
cat <<'WSGI' >/opt/wger/wsgi_wrapper.py
import os
from pathlib import Path

env_file = Path('/opt/wger/.env')
if env_file.exists():
    for line in env_file.read_text().splitlines():
        if line.strip() and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            os.environ.setdefault(key.strip(), value.strip())

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'settings.main')

from wger.wsgi import application
WSGI
set -a && source /opt/wger/.env && set +a
export DJANGO_SETTINGS_MODULE=settings.main
$STD uv run python manage.py migrate
$STD uv run python manage.py loaddata languages
$STD uv run python manage.py loaddata gym_config
$STD uv run python manage.py loaddata groups
$STD uv run python manage.py loaddata site
$STD uv run python manage.py collectstatic --no-input
cat <<EOF | uv run python manage.py shell
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('admin', email='admin@localhost', password='${PG_DB_PASS}')
user.is_superuser = True
user.is_staff = True
user.save()
EOF
msg_ok "Set up wger"

msg_info "Creating Service"
cat <<EOF >/etc/apache2/sites-available/wger.conf
<Directory /opt/wger>
    <Files wsgi_wrapper.py>
        Require all granted
    </Files>
</Directory>

<VirtualHost *:80>
    WSGIApplicationGroup %{GLOBAL}
    WSGIDaemonProcess wger python-path=/opt/wger python-home=/opt/wger/.venv
    WSGIProcessGroup wger
    WSGIScriptAlias / /opt/wger/wsgi_wrapper.py
    WSGIPassAuthorization On

    Alias /static/ /opt/wger/static/
    <Directory /opt/wger/static>
        Require all granted
    </Directory>

    Alias /media/ /opt/wger/media/
    <Directory /opt/wger/media>
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/wger-error.log
    CustomLog /var/log/apache2/wger-access.log combined
</VirtualHost>
EOF
$STD a2dissite 000-default.conf
$STD a2ensite wger
systemctl restart apache2
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
