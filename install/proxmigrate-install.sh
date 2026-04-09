#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: csd440
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/backupassure/proxmigrate

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  gcc \
  libldap-dev \
  libsasl2-dev \
  libssl-dev \
  nginx \
  redis-server \
  openssl \
  openssh-client \
  rsync \
  wget
msg_ok "Installed Dependencies"

msg_info "Deploying ProxMigrate"
fetch_and_deploy_gh_release "proxmigrate" "backupassure/proxmigrate" "tarball"
msg_ok "Deployed ProxMigrate"

msg_info "Creating System User"
useradd --system --home /opt/proxmigrate --shell /sbin/nologin proxmigrate 2>/dev/null || true
chown -R proxmigrate:proxmigrate /opt/proxmigrate
msg_ok "Created System User"

msg_info "Setting Up Python Environment"
python3 -m venv /opt/proxmigrate/venv
chown -R proxmigrate:proxmigrate /opt/proxmigrate/venv
$STD sudo -u proxmigrate /opt/proxmigrate/venv/bin/pip install --quiet --upgrade pip
$STD sudo -u proxmigrate /opt/proxmigrate/venv/bin/pip install --quiet -r /opt/proxmigrate/requirements.txt
msg_ok "Set Up Python Environment"

msg_info "Creating Runtime Directories"
mkdir -p /opt/proxmigrate/uploads \
  /opt/proxmigrate/certs \
  /opt/proxmigrate/certs/acme-challenge \
  /opt/proxmigrate/.ssh \
  /var/log/proxmigrate \
  /run/proxmigrate
chmod 700 /opt/proxmigrate/.ssh
chown -R proxmigrate:proxmigrate /opt/proxmigrate/uploads \
  /opt/proxmigrate/certs \
  /opt/proxmigrate/.ssh \
  /var/log/proxmigrate \
  /run/proxmigrate
msg_ok "Created Runtime Directories"

msg_info "Generating SSL Certificate"
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout /opt/proxmigrate/certs/proxmigrate.key \
  -out /opt/proxmigrate/certs/proxmigrate.crt \
  -subj "/CN=proxmigrate/O=ProxMigrate/C=US" 2>/dev/null
chmod 600 /opt/proxmigrate/certs/proxmigrate.key
chown -R proxmigrate:proxmigrate /opt/proxmigrate/certs
msg_ok "Generated SSL Certificate"

msg_info "Generating SSH Keypair"
ssh-keygen -t rsa -b 4096 -N "" \
  -C "proxmigrate@$(hostname -f 2>/dev/null || hostname)" \
  -f /opt/proxmigrate/.ssh/id_rsa 2>/dev/null
chmod 600 /opt/proxmigrate/.ssh/id_rsa
chmod 644 /opt/proxmigrate/.ssh/id_rsa.pub
chown -R proxmigrate:proxmigrate /opt/proxmigrate/.ssh
msg_ok "Generated SSH Keypair"

msg_info "Configuring Application"
SECRET_KEY="$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")"
FIELD_ENCRYPTION_KEY="$(python3 -c "import base64,os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())")"
cat > /opt/proxmigrate/.env <<EOF
SECRET_KEY=${SECRET_KEY}
DEBUG=False
ALLOWED_HOSTS=*
WEB_PORT=8443
DB_PATH=/opt/proxmigrate/db.sqlite3
UPLOAD_ROOT=/opt/proxmigrate/uploads
FIELD_ENCRYPTION_KEY=${FIELD_ENCRYPTION_KEY}
CELERY_BROKER_URL=redis://127.0.0.1:6379/0
CELERY_RESULT_BACKEND=redis://127.0.0.1:6379/0
EOF
chmod 600 /opt/proxmigrate/.env
chown proxmigrate:proxmigrate /opt/proxmigrate/.env
msg_ok "Configured Application"

msg_info "Running Database Migrations"
$STD sudo -u proxmigrate \
  DJANGO_SETTINGS_MODULE=proxmigrate.settings.production \
  /opt/proxmigrate/venv/bin/python /opt/proxmigrate/manage.py migrate --noinput \
  --settings=proxmigrate.settings.production
$STD sudo -u proxmigrate \
  DJANGO_SETTINGS_MODULE=proxmigrate.settings.production \
  /opt/proxmigrate/venv/bin/python /opt/proxmigrate/manage.py collectstatic --noinput \
  --settings=proxmigrate.settings.production
msg_ok "Database Migrations Complete"

msg_info "Downloading Frontend Assets"
VENDOR_STATIC="/opt/proxmigrate/static/vendor"
mkdir -p "${VENDOR_STATIC}/css" "${VENDOR_STATIC}/webfonts"
$STD wget -q --timeout=30 "https://cdn.jsdelivr.net/npm/bulma@0.9.4/css/bulma.min.css" \
  -O "${VENDOR_STATIC}/css/bulma.min.css" || true
FA_VER="6.5.1"
FA_BASE="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/${FA_VER}"
$STD wget -q --timeout=30 "${FA_BASE}/css/all.min.css" \
  -O "${VENDOR_STATIC}/css/all.min.css" || true
for font in fa-brands-400 fa-regular-400 fa-solid-900 fa-v4compatibility; do
  $STD wget -q --timeout=30 "${FA_BASE}/webfonts/${font}.woff2" \
    -O "${VENDOR_STATIC}/webfonts/${font}.woff2" || true
done
if [[ -f "${VENDOR_STATIC}/css/all.min.css" ]]; then
  sed -i 's|../webfonts/|/static/vendor/webfonts/|g' "${VENDOR_STATIC}/css/all.min.css"
fi
chown -R proxmigrate:proxmigrate "${VENDOR_STATIC}"
$STD sudo -u proxmigrate \
  DJANGO_SETTINGS_MODULE=proxmigrate.settings.production \
  /opt/proxmigrate/venv/bin/python /opt/proxmigrate/manage.py collectstatic --noinput \
  --settings=proxmigrate.settings.production
msg_ok "Downloaded Frontend Assets"

msg_info "Creating Admin User"
sudo -u proxmigrate \
  DJANGO_SUPERUSER_USERNAME="admin" \
  DJANGO_SUPERUSER_PASSWORD="Password!" \
  DJANGO_SUPERUSER_EMAIL="admin@localhost" \
  DJANGO_SETTINGS_MODULE=proxmigrate.settings.production \
  /opt/proxmigrate/venv/bin/python /opt/proxmigrate/manage.py createsuperuser \
  --noinput --settings=proxmigrate.settings.production 2>/dev/null || true
sudo -u proxmigrate \
  DJANGO_SETTINGS_MODULE=proxmigrate.settings.production \
  /opt/proxmigrate/venv/bin/python /opt/proxmigrate/manage.py set_must_change_password admin \
  --settings=proxmigrate.settings.production 2>/dev/null || true
msg_ok "Created Admin User"

msg_info "Configuring Nginx"
cat > /etc/nginx/sites-available/proxmigrate <<'NGINX'
upstream proxmigrate_app {
    server unix:/run/proxmigrate/gunicorn.sock fail_timeout=0;
}

upstream proxmigrate_ws {
    server unix:/run/proxmigrate/daphne.sock fail_timeout=0;
}

server {
    listen 8443 ssl;
    server_name _;

    ssl_certificate     /opt/proxmigrate/certs/proxmigrate.crt;
    ssl_certificate_key /opt/proxmigrate/certs/proxmigrate.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    client_max_body_size 50G;
    proxy_read_timeout   3600s;
    proxy_send_timeout   3600s;
    proxy_connect_timeout 75s;

    location /static/ {
        alias /opt/proxmigrate/staticfiles/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location /ws/ {
        proxy_pass          http://proxmigrate_ws;
        proxy_http_version  1.1;
        proxy_set_header    Upgrade           $http_upgrade;
        proxy_set_header    Connection        "upgrade";
        proxy_set_header    Host              $http_host;
        proxy_set_header    X-Real-IP         $remote_addr;
        proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
        proxy_read_timeout  86400s;
        proxy_send_timeout  86400s;
    }

    location / {
        proxy_pass          http://proxmigrate_app;
        proxy_set_header    Host              $http_host;
        proxy_set_header    X-Real-IP         $remote_addr;
        proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
        proxy_redirect      off;
        proxy_request_buffering off;
    }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/proxmigrate /etc/nginx/sites-enabled/proxmigrate
touch /opt/proxmigrate/deploy/acme-challenge.conf
touch /opt/proxmigrate/deploy/proxmox_ws.conf
chown proxmigrate:proxmigrate /opt/proxmigrate/deploy/acme-challenge.conf /opt/proxmigrate/deploy/proxmox_ws.conf
cat > /etc/sudoers.d/proxmigrate-nginx <<SUDOERS
proxmigrate ALL=(ALL) NOPASSWD: /usr/sbin/nginx -s reload
proxmigrate ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t
proxmigrate ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/nginx/sites-available/proxmigrate
proxmigrate ALL=(ALL) NOPASSWD: /usr/bin/tee /opt/proxmigrate/deploy/acme-challenge.conf
SUDOERS
chmod 440 /etc/sudoers.d/proxmigrate-nginx
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<'EOF' >/etc/systemd/system/proxmigrate-gunicorn.service
[Unit]
Description=ProxMigrate Gunicorn application server
After=network.target

[Service]
Type=simple
User=proxmigrate
Group=proxmigrate
WorkingDirectory=/opt/proxmigrate
EnvironmentFile=/opt/proxmigrate/.env
RuntimeDirectory=proxmigrate
RuntimeDirectoryMode=0755
ExecStart=/opt/proxmigrate/venv/bin/gunicorn \
    --workers 3 \
    --bind unix:/run/proxmigrate/gunicorn.sock \
    --timeout 3600 \
    --log-level info \
    --access-logfile /var/log/proxmigrate/gunicorn-access.log \
    --error-logfile /var/log/proxmigrate/gunicorn-error.log \
    proxmigrate.wsgi:application
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/proxmigrate-celery.service
[Unit]
Description=ProxMigrate Celery worker
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=proxmigrate
Group=proxmigrate
WorkingDirectory=/opt/proxmigrate
EnvironmentFile=/opt/proxmigrate/.env
ExecStart=/opt/proxmigrate/venv/bin/celery \
    -A proxmigrate worker \
    -l info \
    --concurrency=4 \
    -B \
    --schedule=/opt/proxmigrate/celerybeat-schedule
Restart=always
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/proxmigrate-daphne.service
[Unit]
Description=ProxMigrate Daphne WebSocket server
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=proxmigrate
Group=proxmigrate
WorkingDirectory=/opt/proxmigrate
EnvironmentFile=/opt/proxmigrate/.env
RuntimeDirectory=proxmigrate
RuntimeDirectoryMode=0755
RuntimeDirectoryPreserve=yes
ExecStart=/opt/proxmigrate/venv/bin/daphne \
    -u /run/proxmigrate/daphne.sock \
    --access-log /var/log/proxmigrate/daphne-access.log \
    --verbosity 1 \
    proxmigrate.asgi:application
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server proxmigrate-gunicorn proxmigrate-celery proxmigrate-daphne nginx
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
