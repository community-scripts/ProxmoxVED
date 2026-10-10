#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nícolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.jumpserver.org/ | Github: https://github.com/jumpserver/jumpserver

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  pkg-config \
  default-libmysqlclient-dev \
  freetds-dev \
  gettext \
  locales \
  libkrb5-dev \
  libldap2-dev \
  libsasl2-dev \
  libcairo2-dev \
  libjpeg62-turbo-dev \
  libpng-dev \
  uuid-dev \
  libavcodec-dev \
  libavformat-dev \
  libavutil-dev \
  libswscale-dev \
  freerdp3-dev \
  libwinpr3-dev \
  libpango1.0-dev \
  libssh2-1-dev \
  libtelnet-dev \
  libvncserver-dev \
  libwebsockets-dev \
  libpulse-dev \
  libssl-dev \
  libvorbis-dev \
  libwebp-dev \
  redis-server \
  nginx
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="jumpserver" PG_DB_USER="jumpserver" setup_postgresql_db

msg_info "Starting Redis"
systemctl enable -q --now redis-server
msg_ok "Started Redis"

PYTHON_VERSION="3.14" setup_uv

fetch_and_deploy_from_url "https://dlcdn.apache.org/guacamole/1.5.5/source/guacamole-server-1.5.5.tar.gz" "/opt/guacamole-server"

msg_info "Building guacd"
cd /opt/guacamole-server
find . -exec touch -t 202401010000 {} +
touch -t 202401010001 configure.ac aclocal.m4 config.h.in
touch -t 202401010002 configure
find . -name "Makefile.in" -exec touch -t 202401010003 {} +
$STD ./configure --with-systemd-dir=/etc/systemd/system --disable-guacenc
$STD make -j"$(nproc)"
$STD make install
$STD ldconfig
systemctl enable -q --now guacd
msg_ok "Built guacd"

fetch_and_deploy_gh_release "jumpserver" "jumpserver/jumpserver" "tarball" "latest" "" "" "v4."

JMS_BOOTSTRAP_TOKEN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)

msg_info "Configuring JumpServer Core"
cat <<EOF >/opt/jumpserver/config.yml
SECRET_KEY: $(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | cut -c1-49)
BOOTSTRAP_TOKEN: ${JMS_BOOTSTRAP_TOKEN}
DB_ENGINE: postgresql
DB_HOST: 127.0.0.1
DB_PORT: 5432
DB_USER: jumpserver
DB_PASSWORD: ${PG_DB_PASS}
DB_NAME: jumpserver
REDIS_HOST: 127.0.0.1
REDIS_PORT: 6379
HTTP_BIND_HOST: 0.0.0.0
HTTP_LISTEN_PORT: 8080
WS_LISTEN_PORT: 8070
LOG_LEVEL: ERROR
EOF
cd /opt/jumpserver
$STD bash requirements/static_files.sh
$STD uv venv --python 3.14
$STD uv pip install -r pyproject.toml
JMS_GALAXY_RETRIES=3
until ANSIBLE_COLLECTIONS_PATHS="/opt/jumpserver/.venv/lib/python3.14/site-packages/ansible_collections" $STD .venv/bin/ansible-galaxy collection install -r requirements/collections.yml --force --ignore-certs; do
  JMS_GALAXY_RETRIES=$((JMS_GALAXY_RETRIES - 1))
  if ((JMS_GALAXY_RETRIES <= 0)); then
    msg_error "ansible-galaxy collection install failed after 3 attempts (Ansible Galaxy may be unreachable)"
    exit 1
  fi
  sleep 15
done
msg_ok "Configured JumpServer Core"

msg_info "Creating Core Service"
cat <<EOF >/etc/systemd/system/jumpserver.service
[Unit]
Description=JumpServer Core Service
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/jumpserver
Environment=ANSIBLE_COLLECTIONS_PATHS=/opt/jumpserver/.venv/lib/python3.14/site-packages/ansible_collections
Environment=PATH=/opt/jumpserver/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/jumpserver/.venv/bin/python3 /opt/jumpserver/jms start all
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now jumpserver
msg_ok "Created Core Service"

msg_info "Securing Admin Account"
for _ in $(seq 1 90); do
  curl -fsS -o /dev/null http://127.0.0.1:8080/api/health/ 2>/dev/null && break
  sleep 5
done
JMS_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
PYTHONPATH=/opt/jumpserver/apps DJANGO_SETTINGS_MODULE=jumpserver.settings $STD .venv/bin/python3 -c "
import django
django.setup()
from users.models import User
u = User.objects.get(username='admin')
u.set_password('${JMS_ADMIN_PASS}')
u.need_update_password = False
u.save()
"
cat <<EOF >~/jumpserver.creds
JumpServer Admin Credentials
Username: admin
Password: ${JMS_ADMIN_PASS}
EOF
msg_ok "Secured Admin Account"

fetch_and_deploy_gh_release "koko" "jumpserver/koko" "prebuild" "latest" "/opt/koko" "koko-v4.*-linux-$(arch_resolve amd64 arm64).tar.gz" "v4."

msg_info "Configuring KoKo"
cat <<EOF >/opt/koko/config.yml
CORE_HOST: http://127.0.0.1:8080
BOOTSTRAP_TOKEN: ${JMS_BOOTSTRAP_TOKEN}
REDIS_HOST: 127.0.0.1
REDIS_PORT: 6379
EOF
cat <<EOF >/etc/systemd/system/koko.service
[Unit]
Description=JumpServer KoKo Service
After=network.target jumpserver.service

[Service]
Type=simple
WorkingDirectory=/opt/koko
ExecStart=/opt/koko/koko
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now koko
msg_ok "Configured KoKo"

fetch_and_deploy_gh_release "lion" "jumpserver/lion-release" "prebuild" "latest" "/opt/lion" "lion-v*-linux-$(arch_resolve amd64 arm64).tar.gz"

msg_info "Configuring Lion"
cat <<EOF >/opt/lion/config.yml
CORE_HOST: http://127.0.0.1:8080
BOOTSTRAP_TOKEN: ${JMS_BOOTSTRAP_TOKEN}
GUA_HOST: 127.0.0.1
GUA_PORT: 4822
REDIS_HOST: 127.0.0.1
REDIS_PORT: 6379
EOF
cat <<EOF >/etc/systemd/system/lion.service
[Unit]
Description=JumpServer Lion Service
After=network.target guacd.service jumpserver.service

[Service]
Type=simple
WorkingDirectory=/opt/lion
ExecStart=/opt/lion/lion
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now lion
msg_ok "Configured Lion"

fetch_and_deploy_gh_release "lina" "jumpserver/lina" "prebuild" "latest" "/opt/lina" "lina-v4.*.tar.gz" "v4."
fetch_and_deploy_gh_release "luna" "jumpserver/luna" "prebuild" "latest" "/opt/luna" "luna-v4.*.tar.gz" "v4."

msg_info "Configuring Nginx"
rm -f /etc/nginx/sites-enabled/default
cat <<EOF >/etc/nginx/sites-available/jumpserver
server {
    listen 80 default_server;
    client_max_body_size 4096m;

    location / {
        rewrite ^/(.*)\$ /ui/\$1 last;
    }

    location /ui/ {
        try_files \$uri / /index.html;
        alias /opt/lina/;
    }

    location /luna/ {
        try_files \$uri / /index.html;
        alias /opt/luna/;
    }

    location /static/ {
        root /opt/jumpserver/data/;
    }

    location /private-media/ {
        internal;
        alias /opt/jumpserver/data/media/;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location ~ ^/(core|api|media)/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_ignore_client_abort on;
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 6000;
    }

    location /koko/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_ignore_client_abort on;
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 6000;
    }

    location /lion/ {
        proxy_pass http://127.0.0.1:8081;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_ignore_client_abort on;
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 6000;
    }
}
EOF
ln -sf /etc/nginx/sites-available/jumpserver /etc/nginx/sites-enabled/jumpserver
systemctl enable -q nginx
systemctl restart nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
