#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Blarm1959
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Dispatcharr/Dispatcharr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Suppress apt-listchanges mails and prompts during automated install
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export APT_LISTCHANGES_NO_MAIL=1

# Application location
APP_DIR="/opt/dispatcharr"

# Variables
APP="Dispatcharr"
DISPATCH_USER="dispatcharr"
DISPATCH_GROUP="dispatcharr"
APP_DIR="/opt/dispatcharr"

PG_VERSION="17"
PG_CLUSTER="main"
PG_DATADIR="/data/db"
POSTGRES_DB="dispatcharr"
POSTGRES_USER="dispatch"
POSTGRES_PASSWORD=""
CREDS_FILE="/root/dispatcharr.creds"

NODE_VERSION="24"

NGINX_HTTP_PORT="9191"
WEBSOCKET_PORT="8001"
GUNICORN_RUNTIME_DIR="dispatcharr"
GUNICORN_SOCKET="/run/${GUNICORN_RUNTIME_DIR}/dispatcharr.sock"
SYSTEMD_DIR="/etc/systemd/system"
NGINX_SITE="/etc/nginx/sites-available/dispatcharr.conf"
NGINX_SITE_ENABLED="${NGINX_SITE/sites-available/sites-enabled}"

SERVER_IP="$(hostname -I | tr -s ' ' | cut -d' ' -f1)"

APP_LC=$(echo "${APP,,}" | tr -d ' ')
VERSION_FILE="$HOME/.${APP_LC}"

msg_info "Installing core packages"
$STD apt-get update
declare -a packages=(
  git curl wget sudo
  build-essential libpq-dev libffi-dev pkg-config
  nginx redis-server ffmpeg procps streamlink
)
$STD apt-get install -y --no-install-recommends "${packages[@]}"
msg_ok "Core packages installed"

msg_info "Installing uv (Python package manager)"
# Use latest Python via uv on Debian 13
PYTHON_VERSION="3.13" setup_uv
msg_ok "uv installed"

msg_info "Preparing user and directories"
if ! getent group "$DISPATCH_GROUP" >/dev/null; then
  $STD groupadd "$DISPATCH_GROUP"
fi
if ! id -u "$DISPATCH_USER" >/dev/null 2>&1; then
  $STD useradd -m -g "$DISPATCH_GROUP" -s /bin/bash "$DISPATCH_USER"
fi
install -d -m 0755 -o "$DISPATCH_USER" -g "$DISPATCH_GROUP" "$APP_DIR"
msg_ok "User and directories ready"

msg_info "Creating application directories"
install -d -m 0755 -o "$DISPATCH_USER" -g "$DISPATCH_GROUP" /data
install -d -m 0755 -o "$DISPATCH_USER" -g "$DISPATCH_GROUP" \
  /data/m3us /data/epgs /data/logos \
  /data/uploads/m3us /data/uploads/epgs \
  /data/recordings /data/plugins
install -d -m 0755 -o "$DISPATCH_USER" -g "$DISPATCH_GROUP" \
  "${APP_DIR}/logo_cache" "${APP_DIR}/media"
msg_ok "Application directories ready"

msg_info "Installing Node.js"
NODE_VERSION="$NODE_VERSION" setup_nodejs
msg_ok "Node.js installed"

msg_info "Installing PostgreSQL"
PG_VERSION="$PG_VERSION" setup_postgresql
msg_ok "PostgreSQL installed"

msg_info "Reconfiguring PostgreSQL ${PG_VERSION}/${PG_CLUSTER} to ${PG_DATADIR}"
# Strict perms are REQUIRED by Postgres
install -d -m 0700 -o postgres -g postgres "${PG_DATADIR}"
# Drop default cluster (if present) and recreate pointing at the new datadir
$STD sudo -u postgres pg_dropcluster --stop "${PG_VERSION}" "${PG_CLUSTER}"
$STD sudo -u postgres pg_createcluster --datadir="${PG_DATADIR}" "${PG_VERSION}" "${PG_CLUSTER}"
# Start this specific cluster and wait for readiness
$STD pg_ctlcluster "${PG_VERSION}" "${PG_CLUSTER}" start
for _ in {1..20}; do sudo -u postgres pg_isready -q && break; sleep 0.5; done
msg_ok "PostgreSQL ${PG_VERSION}/${PG_CLUSTER} running from ${PG_DATADIR}"

msg_info "Provisioning PostgreSQL database and role"
POSTGRES_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
{
    echo "Dispatcharr-Credentials"
    echo "Dispatcharr Database User: $POSTGRES_USER"
    echo "Dispatcharr Database Password: $POSTGRES_PASSWORD"
    echo "Dispatcharr Database Name: $POSTGRES_DB"
} >>$CREDS_FILE
chmod 0600 $CREDS_FILE
$STD sudo -u postgres createdb "${POSTGRES_DB}"
$STD sudo -u postgres psql -c "CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};"
$STD sudo -u postgres psql -c "ALTER DATABASE ${POSTGRES_DB} OWNER TO ${POSTGRES_USER};"
$STD sudo -u postgres psql -d "${POSTGRES_DB}" -c "ALTER SCHEMA public OWNER TO ${POSTGRES_USER};"
msg_ok "PostgreSQL database and role provisioned"

msg_info "Fetching Dispatcharr (latest GitHub release)"
fetch_and_deploy_gh_release "dispatcharr" "Dispatcharr/Dispatcharr"
$STD chown -R "$DISPATCH_USER:$DISPATCH_GROUP" "$APP_DIR"
CURRENT_VERSION=""
[[ -f "$VERSION_FILE" ]] && CURRENT_VERSION=$(<"$VERSION_FILE")
msg_ok "Dispatcharr deployed to ${APP_DIR}"

msg_info "Setting up Python virtual environment and backend dependencies (uv)"
export UV_INDEX_URL="https://pypi.org/simple"
export UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cpu"
export UV_INDEX_STRATEGY="unsafe-best-match"
$STD runuser -u "$DISPATCH_USER" -- bash -c 'cd "'"${APP_DIR}"'"; uv venv --seed env || uv venv env'

# Build a filtered requirements without uWSGI
# Ensure APP_DIR is visible to the child shell
runuser -u "$DISPATCH_USER" -- env APP_DIR="$APP_DIR" bash -s <<'BASH'
set -e
cd "$APP_DIR"
REQ=requirements.txt
REQF=requirements.nouwsgi.txt
if [ -f "$REQ" ]; then
  if grep -qiE '^\s*uwsgi(\b|[<>=~])' "$REQ"; then
    sed -E '/^\s*uwsgi(\b|[<>=~]).*/Id' "$REQ" > "$REQF"
  else
    cp "$REQ" "$REQF"
  fi
fi
BASH

runuser -u "$DISPATCH_USER" -- bash -c 'cd "'"${APP_DIR}"'"; . env/bin/activate; uv pip install -q -r requirements.nouwsgi.txt'
runuser -u "$DISPATCH_USER" -- bash -c 'cd "'"${APP_DIR}"'"; . env/bin/activate; uv pip install -q gunicorn'
ln -sf /usr/bin/ffmpeg "${APP_DIR}/env/bin/ffmpeg"
msg_ok "Python virtual environment ready"

msg_info "Building frontend"
sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}/frontend\"; rm -rf node_modules .cache dist build .next"
sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}/frontend\"; if [ -f package-lock.json ]; then npm ci --silent --no-progress --no-audit --no-fund; else npm install --legacy-peer-deps --silent --no-progress --no-audit --no-fund; fi"
$STD sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}/frontend\"; npm run build --loglevel=error -- --logLevel error"
msg_ok "Frontend built"

msg_info "Running Django migrations and collectstatic"
$STD sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}\"; source env/bin/activate; POSTGRES_DB='${POSTGRES_DB}' POSTGRES_USER='${POSTGRES_USER}' POSTGRES_PASSWORD='${POSTGRES_PASSWORD}' POSTGRES_HOST=localhost python manage.py migrate --noinput"
$STD sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}\"; source env/bin/activate; python manage.py collectstatic --noinput"
msg_ok "Django tasks complete"

msg_info "Writing systemd services and Nginx config"
cat <<EOF >${SYSTEMD_DIR}/dispatcharr.service
[Unit]
Description=Gunicorn for Dispatcharr
After=network.target postgresql.service redis-server.service

[Service]
User=${DISPATCH_USER}
Group=${DISPATCH_GROUP}
WorkingDirectory=${APP_DIR}
RuntimeDirectory=${GUNICORN_RUNTIME_DIR}
RuntimeDirectoryMode=0775
Environment="PATH=${APP_DIR}/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
Environment="POSTGRES_DB=${POSTGRES_DB}"
Environment="POSTGRES_USER=${POSTGRES_USER}"
Environment="POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
Environment="POSTGRES_HOST=localhost"
ExecStartPre=/usr/bin/bash -c 'until pg_isready -h localhost -U ${POSTGRES_USER}; do sleep 1; done'
ExecStart=${APP_DIR}/env/bin/gunicorn \
    --workers=4 \
    --worker-class=gevent \
    --timeout=300 \
    --bind unix:${GUNICORN_SOCKET} \
    dispatcharr.wsgi:application
Restart=always
KillMode=mixed
SyslogIdentifier=dispatcharr
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >${SYSTEMD_DIR}/dispatcharr-celery.service
[Unit]
Description=Celery Worker for Dispatcharr
After=network.target redis-server.service
Requires=dispatcharr.service

[Service]
User=${DISPATCH_USER}
Group=${DISPATCH_GROUP}
WorkingDirectory=${APP_DIR}
Environment="PATH=${APP_DIR}/env/bin"
Environment="POSTGRES_DB=${POSTGRES_DB}"
Environment="POSTGRES_USER=${POSTGRES_USER}"
Environment="POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
Environment="POSTGRES_HOST=localhost"
Environment="CELERY_BROKER_URL=redis://localhost:6379/0"
ExecStart=${APP_DIR}/env/bin/celery -A dispatcharr worker -l info
Restart=always
KillMode=mixed
SyslogIdentifier=dispatcharr-celery
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >${SYSTEMD_DIR}/dispatcharr-celerybeat.service
[Unit]
Description=Celery Beat Scheduler for Dispatcharr
After=network.target redis-server.service
Requires=dispatcharr.service

[Service]
User=${DISPATCH_USER}
Group=${DISPATCH_GROUP}
WorkingDirectory=${APP_DIR}
Environment="PATH=${APP_DIR}/env/bin"
Environment="POSTGRES_DB=${POSTGRES_DB}"
Environment="POSTGRES_USER=${POSTGRES_USER}"
Environment="POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
Environment="POSTGRES_HOST=localhost"
Environment="CELERY_BROKER_URL=redis://localhost:6379/0"
ExecStart=${APP_DIR}/env/bin/celery -A dispatcharr beat -l info
Restart=always
KillMode=mixed
SyslogIdentifier=dispatcharr-celerybeat
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >${SYSTEMD_DIR}/dispatcharr-daphne.service
[Unit]
Description=Daphne for Dispatcharr (ASGI/WebSockets)
After=network.target
Requires=dispatcharr.service

[Service]
User=${DISPATCH_USER}
Group=${DISPATCH_GROUP}
WorkingDirectory=${APP_DIR}
Environment="PATH=${APP_DIR}/env/bin"
Environment="POSTGRES_DB=${POSTGRES_DB}"
Environment="POSTGRES_USER=${POSTGRES_USER}"
Environment="POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
Environment="POSTGRES_HOST=localhost"
ExecStart=${APP_DIR}/env/bin/daphne -b 0.0.0.0 -p ${WEBSOCKET_PORT} dispatcharr.asgi:application
Restart=always
KillMode=mixed
SyslogIdentifier=dispatcharr-daphne
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >"${NGINX_SITE}"
server {
    listen ${NGINX_HTTP_PORT};
    location / {
        include proxy_params;
        proxy_pass http://unix:${GUNICORN_SOCKET};
    }
    location /static/ {
        alias ${APP_DIR}/static/;
    }
    location /assets/ {
        alias ${APP_DIR}/frontend/dist/assets/;
    }
    location /media/ {
        alias ${APP_DIR}/media/;
    }
    location /ws/ {
        proxy_pass http://127.0.0.1:${WEBSOCKET_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
    }
}
EOF

ln -sf "${NGINX_SITE}" "${NGINX_SITE_ENABLED}"
[ -f /etc/nginx/sites-enabled/default ] && rm /etc/nginx/sites-enabled/default
$STD nginx -t >/dev/null
$STD systemctl restart nginx
$STD systemctl enable nginx
msg_ok "Systemd and Nginx configuration written"

msg_info "Enabling and starting Dispatcharr services"
$STD systemctl daemon-reexec
$STD systemctl daemon-reload
$STD systemctl enable --now dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne
msg_ok "Services are running"

msg_ok "Installed ${APP} : v${CURRENT_VERSION}"

echo "Postgres (See $CREDS_FILE):"
echo "    Database Name: $POSTGRES_DB"
echo "    Database User: $POSTGRES_USER"
echo "    Database Password: $POSTGRES_PASSWORD"
echo

echo "Nginx is listening on port ${NGINX_HTTP_PORT}."
echo "Gunicorn socket: ${GUNICORN_SOCKET}."
echo "WebSockets on port ${WEBSOCKET_PORT} (path /ws/)."
echo
echo "You can check logs via:"
echo "  sudo journalctl -u dispatcharr -f"
echo "  sudo journalctl -u dispatcharr-celery -f"
echo "  sudo journalctl -u dispatcharr-celerybeat -f"
echo "  sudo journalctl -u dispatcharr-daphne -f"
echo
echo "Visit the app at:"
echo "  http://${SERVER_IP}:${NGINX_HTTP_PORT}"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
