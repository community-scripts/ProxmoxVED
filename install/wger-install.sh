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
  libapache2-mod-wsgi-py3
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="yarn,sass" setup_nodejs
setup_uv

fetch_and_deploy_gh_release "wger" "wger-project/wger" "tarball" "latest" "/opt/wger"

msg_info "Setting up wger"
mkdir -p /opt/wger/{db,static,media}
touch /opt/wger/db/database.sqlite
chown :www-data -R /opt/wger/db
chmod g+w /opt/wger/db /opt/wger/db/database.sqlite
chmod o+w /opt/wger/media
cd /opt/wger
$STD uv venv
$STD uv pip install .
mkdir -p /opt/wger/settings
cat <<EOF >/opt/wger/settings/main.py
from wger.settings_global import *

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': '/opt/wger/db/database.sqlite',
    }
}

MEDIA_ROOT = '/opt/wger/media'
STATIC_ROOT = '/opt/wger/static'
EOF
touch /opt/wger/settings/__init__.py
export DJANGO_SETTINGS_MODULE=settings.main
export PYTHONPATH=/opt/wger
$STD uv run python manage.py migrate
$STD uv run python manage.py collectstatic --no-input
msg_ok "Set up wger"

msg_info "Creating Service"
cat <<EOF >/etc/apache2/sites-available/wger.conf
<Directory /opt/wger>
    <Files wsgi.py>
        Require all granted
    </Files>
</Directory>

<VirtualHost *:80>
    WSGIApplicationGroup %{GLOBAL}
    WSGIDaemonProcess wger python-path=/opt/wger python-home=/opt/wger/.venv
    WSGIProcessGroup wger
    WSGIScriptAlias / /opt/wger/wger/wsgi.py
    WSGIPassAuthorization On
    SetEnv DJANGO_SETTINGS_MODULE settings.main
    SetEnv PYTHONPATH /opt/wger

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
