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


APPLICATION="Dispatcharr"
APP_NAME="dispatcharr"
APP_USER="dispatcharr"
APP_GROUP="dispatcharr"
APP_DIR="/opt/dispatcharr"
GUNICORN_RUNTIME_DIR="dispatcharr"
GUNICORN_PORT="5656"
NGINX_HTTP_PORT="9191"
WEBSOCKET_PORT="8001"

msg_info "Creating ${APP_USER} user"
groupadd -f $APP_GROUP
useradd -M -s /usr/sbin/nologin -g $APP_GROUP $APP_USER || true
msg_ok "Created ${APP_USER} user"

setup_uv
NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  curl \
  wget \
  build-essential \
  gcc \
  libpcre3-dev \
  libpq-dev \
  python3-dev \
  python3-venv \
  python3-pip \
  nginx \
  redis-server \
  ffmpeg \
  procps \
  streamlink
msg_ok "Installed Dependencies"

msg_info "Configuring PostgreSQL"

POSTGRES_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

{
  echo "POSTGRES_DB=dispatcharr"
  echo "POSTGRES_USER=dispatch"
  echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
  echo "POSTGRES_HOST=localhost"
} >> ~/.$APP_NAME.creds

source ~/.$APP_NAME.creds

su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}'\"" | grep -q 1 || \
  su - postgres -c "psql -c \"CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';\""

su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'\"" | grep -q 1 || \
  su - postgres -c "psql -c \"CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};\""

su - postgres -c "psql -d ${POSTGRES_DB} -c \"ALTER SCHEMA public OWNER TO ${POSTGRES_USER};\""



msg_ok "Configured PostgreSQL"

msg_info "Fetching latest Dispatcharr release version"
LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/Dispatcharr/Dispatcharr/releases/latest | grep '"tag_name":' | cut -d '"' -f4)

if [[ -z "$LATEST_VERSION" ]]; then
  msg_error "Failed to fetch latest release version from GitHub."
  exit 1
fi

msg_info "Downloading Dispatcharr $LATEST_VERSION"
fetch_and_deploy_gh_release "dispatcharr" "Dispatcharr/Dispatcharr"
echo "$LATEST_VERSION" > "/opt/${APPLICATION}_version.txt"
mkdir -p /data/{db,epgs,logos,m3us,recordings,uploads}
mkdir -p /etc/$APP_NAME
cp ~/.$APP_NAME.creds /etc/$APP_NAME/$APP_NAME.env
chown -R "$APP_USER:$APP_GROUP" {/etc/$APP_NAME,$APP_DIR,/data}


sed -i 's/program\[\x27channel_id\x27\]/program["channel_id"]/g' "${APP_DIR}/apps/output/views.py"

msg_ok "Downloaded Dispatcharr $LATEST_VERSION"

msg_info "Install Python Requirements"
cd $APP_DIR
python3 -m venv env
source env/bin/activate

$STD pip install --upgrade pip
$STD pip install -r requirements.txt
$STD pip install gunicorn
ln -sf /usr/bin/ffmpeg $APP_DIR/env/bin/ffmpeg
msg_ok "Python Requirements Installed"

msg_info "Building Frontend"
cd $APP_DIR/frontend
$STD npm install --legacy-peer-deps
$STD npm run build
msg_ok "Built Frontend"

msg_info "Running Django Migrations"
cd $APP_DIR
source env/bin/activate
set -o allexport
source /etc/$APP_NAME/$APP_NAME.env
set +o allexport

$STD python manage.py migrate --noinput
$STD python manage.py collectstatic --noinput
msg_ok "Migrations Complete"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/dispatcharr.conf
server {
    listen $NGINX_HTTP_PORT;

    location / {
        include proxy_params;
        proxy_pass http://127.0.0.1:$GUNICORN_PORT;
    }

    location /static/ {
        alias $APP_DIR/static/;
    }

    location /assets/ {
        alias $APP_DIR/frontend/dist/assets/;
    }

    location /media/ {
        alias $APP_DIR/media/;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:$WEBSOCKET_PORT;
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
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
RuntimeDirectory=$GUNICORN_RUNTIME_DIR
RuntimeDirectoryMode=0775
Environment="PATH=$APP_DIR/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
EnvironmentFile=/etc/$APP_NAME/$APP_NAME.env
ExecStart=$APP_DIR/env/bin/gunicorn \\
    --workers=4 \\
    --worker-class=gevent \\
    --timeout=300 \\
    --bind 0.0.0.0:$GUNICORN_PORT \
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
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/env/bin"
EnvironmentFile=/etc/$APP_NAME/$APP_NAME.env
Environment="CELERY_BROKER_URL=redis://localhost:6379/0"
ExecStart=$APP_DIR/env/bin/celery -A dispatcharr worker -l info -c 4
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
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/env/bin"
EnvironmentFile=/etc/$APP_NAME/$APP_NAME.env
Environment="CELERY_BROKER_URL=redis://localhost:6379/0"
ExecStart=$APP_DIR/env/bin/celery -A dispatcharr beat -l info
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
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/env/bin"
EnvironmentFile=/etc/$APP_NAME/$APP_NAME.env
ExecStart=$APP_DIR/env/bin/daphne -b 0.0.0.0 -p $WEBSOCKET_PORT dispatcharr.asgi:application
Restart=always
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

msg_ok "Created systemd services"


msg_info "Starting Dispatcharr Services"
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne
systemctl restart dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne
msg_ok "Started Dispatcharr Services"


motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
