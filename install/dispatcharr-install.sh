#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: ekke85
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Dispatcharr/Dispatcharr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# msg_info "Creating ${APP_USER} user"
# groupadd -f $APP_GROUP
# useradd -M -s /usr/sbin/nologin -g $APP_GROUP $APP_USER || true
# msg_ok "Created ${APP_USER} user"

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  gcc \
  libpcre3-dev \
  libpq-dev \
  nginx \
  redis-server \
  ffmpeg \
  procps \
  streamlink
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.13" setup_uv
NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
fetch_and_deploy_gh_release "dispatcharr" "Dispatcharr/Dispatcharr"

msg_info "Set up PostgreSQL Database"
DB_NAME=dispatcharr_db
DB_USER=dispatcharr_usr
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
DB_URL="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
{
  echo "Dispatcharr-Credentials"
  echo "Dispatcharr Database Name: $DB_NAME"
  echo "Dispatcharr Database User: $DB_USER"
  echo "Dispatcharr Database Password: $DB_PASS"
} >>~/dispatcharr.creds
msg_ok "Set up PostgreSQL Database"

msg_info "Setup Python (uv) requirements (system)"
UV_PY="${PYTHON_VERSION:-3.13}"
$STD uv python install "$UV_PY"
cd /opt/dispatcharr
PYPI_URL="https://pypi.org/simple"
mapfile -t EXTRA_INDEX_URLS < <(grep -E '^(--(extra-)?index-url|-i)\s' requirements.txt 2>/dev/null | awk '{print $2}' | sed 's#/*$##')

UV_INDEX_ARGS=(--index-url "$PYPI_URL" --index-strategy unsafe-best-match)
for u in "${EXTRA_INDEX_URLS[@]}"; do
  [[ -n "$u" && "$u" != "$PYPI_URL" ]] && UV_INDEX_ARGS+=(--extra-index-url "$u")
done
if [[ -f requirements.txt ]]; then
  $STD uv pip install --system "${UV_INDEX_ARGS[@]}" -r requirements.txt
fi
$STD uv pip install --system "${UV_INDEX_ARGS[@]}" gunicorn gevent celery daphne
ln -sf /usr/bin/ffmpeg /opt/dispatcharr/env/bin/ffmpeg
msg_ok "Python Requirements Installed"

msg_info "Building Frontend"
cd /opt/dispatcharr/frontend
$STD npm install --legacy-peer-deps
$STD npm run build
msg_ok "Built Frontend"

msg_info "Running Django Migrations"
cd /opt/dispatcharr
set -o allexport
source /etc/dispatcharr/dispatcharr.env
set +o allexport

$STD ./.venv/bin/python manage.py migrate --noinput
$STD ./.venv/bin/python manage.py collectstatic --noinput
msg_ok "Migrations Complete"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/dispatcharr.conf
server {
    listen 9191;

    location / {
        include proxy_params;
        proxy_pass http://127.0.0.1:5656;
    }

    location /static/ {
        alias /opt/dispatcharr/static/;
    }

    location /assets/ {
        alias /opt/dispatcharr/frontend/dist/assets/;
    }

    location /media/ {
        alias /opt/dispatcharr/media/;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

ln -sf /etc/nginx/sites-available/dispatcharr.conf /etc/nginx/sites-enabled/dispatcharr.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
systemctl enable nginx
msg_ok "Configured Nginx"

msg_info "Creating systemd services"

cat <<EOF >/etc/systemd/system/dispatcharr.service
[Unit]
Description=Gunicorn for Dispatcharr
After=network.target postgresql.service redis-server.service

[Service]
WorkingDirectory=/opt/dispatcharr
RuntimeDirectory=dispatcharr
RuntimeDirectoryMode=0775
Environment="PATH=/opt/dispatcharr/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
EnvironmentFile=/etc/dispatcharr/dispatcharr.env
ExecStart=/opt/dispatcharr/env/bin/gunicorn \\
    --workers=4 \\
    --worker-class=gevent \\
    --timeout=300 \\
    --bind 0.0.0.0:5656 \
    dispatcharr.wsgi:application
Restart=always
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/dispatcharr-celery.service
[Unit]
Description=Celery Worker for Dispatcharr
After=network.target redis-server.service
Requires=dispatcharr.service

[Service]
WorkingDirectory=/opt/dispatcharr
Environment="PATH=/opt/dispatcharr/env/bin"
EnvironmentFile=/etc/dispatcharr/dispatcharr.env
Environment="CELERY_BROKER_URL=redis://localhost:6379/0"
ExecStart=/opt/dispatcharr/env/bin/celery -A dispatcharr worker -l info -c 4
Restart=always
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/dispatcharr-celerybeat.service
[Unit]
Description=Celery Beat Scheduler for Dispatcharr
After=network.target redis-server.service
Requires=dispatcharr.service

[Service]
WorkingDirectory=/opt/dispatcharr
Environment="PATH=/opt/dispatcharr/env/bin"
EnvironmentFile=/etc/dispatcharr/dispatcharr.env
Environment="CELERY_BROKER_URL=redis://localhost:6379/0"
ExecStart=/opt/dispatcharr/env/bin/celery -A dispatcharr beat -l info
Restart=always
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/dispatcharr-daphne.service
[Unit]
Description=Daphne for Dispatcharr (ASGI)
After=network.target
Requires=dispatcharr.service

[Service]
WorkingDirectory=/opt/dispatcharr
Environment="PATH=/opt/dispatcharr/env/bin"
EnvironmentFile=/etc/dispatcharr/dispatcharr.env
ExecStart=/opt/dispatcharr/env/bin/daphne -b 0.0.0.0 -p 8001 dispatcharr.asgi:application
Restart=always
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne
msg_ok "Started Dispatcharr Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
