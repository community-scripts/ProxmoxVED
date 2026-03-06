#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/simple-login/app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
echo "postfix postfix/mailname string $(hostname -f)" | debconf-set-selections
echo "postfix postfix/main_mailer_type string Internet Site" | debconf-set-selections
$STD apt install -y \
  build-essential \
  libre2-dev \
  pkg-config \
  libpq-dev \
  cmake \
  pkg-config \
  git \
  redis-server \
  nginx \
  postfix \
  postfix-pgsql \
  opendkim-tools
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
APPLICATION="simplelogin" PG_DB_NAME="simplelogin" PG_DB_USER="simplelogin" setup_postgresql_db
PYTHON_VERSION="3.12" setup_uv
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "simplelogin" "simple-login/app"

msg_info "Installing SimpleLogin (Patience)"
cd /opt/simplelogin
$STD uv venv
$STD uv pip install setuptools hatchling editables
$STD uv sync --locked --no-dev --no-build-isolation --no-install-package newrelic

VENV_SITE=$(/opt/simplelogin/.venv/bin/python -c "import site; print(site.getsitepackages()[0])")
mkdir -p "${VENV_SITE}/newrelic"
cat <<'STUB' >"${VENV_SITE}/newrelic/__init__.py"
STUB
cat <<'STUB' >"${VENV_SITE}/newrelic/agent.py"
def record_custom_event(*a, **kw): pass
def initialize(*a, **kw): pass
STUB

if [[ -f /opt/simplelogin/static/package.json ]]; then
  cd /opt/simplelogin/static
  $STD npm ci || $STD npm install
fi
msg_ok "Installed SimpleLogin"

msg_info "Configuring SimpleLogin"
FLASK_SECRET=$(openssl rand -hex 32)

mkdir -p /opt/simplelogin/dkim
$STD opendkim-genkey -b 2048 -d example.com -s dkim -D /opt/simplelogin/dkim
chmod 600 /opt/simplelogin/dkim/dkim.private

$STD openssl genrsa -out /opt/simplelogin/openid-rsa.key 2048
$STD openssl rsa -in /opt/simplelogin/openid-rsa.key -pubout -out /opt/simplelogin/openid-rsa.pub

mkdir -p /opt/simplelogin/uploads /opt/simplelogin/.gnupg
chmod 700 /opt/simplelogin/.gnupg

cat <<EOF >/opt/simplelogin/.env
URL=http://${LOCAL_IP}
EMAIL_DOMAIN=example.com
SUPPORT_EMAIL=support@example.com
DB_URI=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost/${PG_DB_NAME}
FLASK_SECRET=${FLASK_SECRET}
DKIM_PRIVATE_KEY_PATH=/opt/simplelogin/dkim/dkim.private
GNUPGHOME=/opt/simplelogin/.gnupg
LOCAL_FILE_UPLOAD=true
UPLOAD_DIR=/opt/simplelogin/uploads
DISABLE_ALIAS_SUFFIX=1
WORDS_FILE_PATH=/opt/simplelogin/local_data/words.txt
NAMESERVERS=1.1.1.1
MEM_STORE_URI=redis://localhost:6379/1
OPENID_PRIVATE_KEY_PATH=/opt/simplelogin/openid-rsa.key
OPENID_PUBLIC_KEY_PATH=/opt/simplelogin/openid-rsa.pub
EOF

cd /opt/simplelogin
$STD .venv/bin/flask db upgrade
$STD .venv/bin/python init_app.py
msg_ok "Configured SimpleLogin"

msg_info "Configuring Postfix"
cat <<EOF >/etc/postfix/pgsql-relay-domains.cf
hosts = localhost
dbname = ${PG_DB_NAME}
user = ${PG_DB_USER}
password = ${PG_DB_PASS}
query = SELECT domain FROM custom_domain WHERE domain='%s' AND verified=true
EOF

cat <<EOF >/etc/postfix/pgsql-transport-maps.cf
hosts = localhost
dbname = ${PG_DB_NAME}
user = ${PG_DB_USER}
password = ${PG_DB_PASS}
query = SELECT 'smtp:[127.0.0.1]:20381' FROM custom_domain WHERE domain='%s' AND verified=true
EOF

chmod 640 /etc/postfix/pgsql-*.cf

cat <<EOF >/etc/postfix/transport
example.com smtp:[127.0.0.1]:20381
EOF
$STD postmap /etc/postfix/transport

postconf -e "relay_domains = example.com, pgsql:/etc/postfix/pgsql-relay-domains.cf"
postconf -e "transport_maps = hash:/etc/postfix/transport, pgsql:/etc/postfix/pgsql-transport-maps.cf"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"
$STD systemctl restart postfix
msg_ok "Configured Postfix"

msg_info "Creating Services"
cat <<'EOF' >/etc/systemd/system/simplelogin-webapp.service
[Unit]
Description=SimpleLogin Web Application
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/simplelogin
ExecStart=/opt/simplelogin/.venv/bin/gunicorn wsgi:app -b 127.0.0.1:7777 -w 2 --timeout 120
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/simplelogin-email.service
[Unit]
Description=SimpleLogin Email Handler
After=network.target postgresql.service redis-server.service postfix.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/simplelogin
ExecStart=/opt/simplelogin/.venv/bin/python email_handler.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/simplelogin-job.service
[Unit]
Description=SimpleLogin Job Runner
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/simplelogin
ExecStart=/opt/simplelogin/.venv/bin/python job_runner.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now redis-server simplelogin-webapp simplelogin-email simplelogin-job
msg_ok "Created Services"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/simplelogin.conf
server {
  listen 80 default_server;
  server_name _;

  client_max_body_size 10M;

  location / {
    proxy_pass http://127.0.0.1:7777;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
EOF
ln -sf /etc/nginx/sites-available/simplelogin.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
$STD systemctl enable --now nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
