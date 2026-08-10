#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/meeb/tubesync

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y ffmpeg nginx
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

fetch_and_deploy_gh_release "tubesync" "meeb/tubesync" "tarball"

msg_info "Installing Python Dependencies"
$STD uv venv /opt/tubesync/.venv
# Resolve deps from the upstream Pipfile into requirements.txt. mysqlclient is
# skipped (native build, only for the optional MySQL backend); libsass is added
# for django-sass-processor's "compilescss".
sed -n '/^\[packages\]/,/^\[/{/=/p}' /opt/tubesync/Pipfile | grep -v '^mysqlclient' |
  sed -E 's/ = \{.*extras = \[([^]]*)\].*/[\1]/; s/ = "\*"//; s/ = "([^"]*)"/\1/; s/[" ]//g' >/opt/tubesync/requirements.txt
$STD uv pip install --python /opt/tubesync/.venv/bin/python -r /opt/tubesync/requirements.txt
$STD uv pip install --python /opt/tubesync/.venv/bin/python libsass
msg_ok "Installed Python Dependencies"

msg_info "Applying TubeSync patches"
# TubeSync ships patches that add the yt_dlp.patch submodule (and hat.syslog
# files) on top of the installed packages - the app imports these at runtime.
SITE_PACKAGES=$(/opt/tubesync/.venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
cp -rf /opt/tubesync/patches/hat/. "$SITE_PACKAGES/hat/"
cp -rf /opt/tubesync/patches/yt_dlp/. "$SITE_PACKAGES/yt_dlp/"
msg_ok "Applied TubeSync patches"

msg_info "Configuring TubeSync"
mkdir -p /opt/tubesync-config/hat /opt/tubesync-downloads
# Derive local_settings.py from the upstream container example and point the
# config/downloads directories at persistent paths outside the app directory.
cp /opt/tubesync/tubesync/tubesync/local_settings.py.container /opt/tubesync/tubesync/tubesync/local_settings.py
sed -i "s|CONFIG_BASE_DIR = ROOT_DIR / 'config'|CONFIG_BASE_DIR = Path('/opt/tubesync-config')|" /opt/tubesync/tubesync/tubesync/local_settings.py
sed -i "s|DOWNLOADS_BASE_DIR = ROOT_DIR / 'downloads'|DOWNLOADS_BASE_DIR = Path('/opt/tubesync-downloads')|" /opt/tubesync/tubesync/tubesync/local_settings.py
# The upstream gunicorn config hardcodes Docker-only values (user/group "app",
# chdir "/app", pidfile under /run/app). Point them at our bare-metal paths.
sed -i \
  -e "s|^user = .*|user = 'root'|" \
  -e "s|^group = .*|group = 'root'|" \
  -e "s|^chdir = .*|chdir = '/opt/tubesync/tubesync'|" \
  -e "s|^pidfile = .*|pidfile = '/run/tubesync/gunicorn.pid'|" \
  /opt/tubesync/tubesync/tubesync/gunicorn.py

SECRET_KEY=$(openssl rand -hex 32)
cat <<EOF >/opt/tubesync.env
DJANGO_SECRET_KEY=${SECRET_KEY}
TUBESYNC_HOSTS=*
# gunicorn listens locally; nginx (port 4848) proxies to it.
LISTEN_HOST=127.0.0.1
LISTEN_PORT=8080
GUNICORN_WORKERS=3
TZ=UTC
PYTHONPATH=/opt/tubesync/tubesync
# Optional: front TubeSync with HTTP basic auth by setting both values
# HTTP_USER=admin
# HTTP_PASS=changeme
# Optional: use an external database instead of SQLite
# PostgreSQL works out of the box:
# DATABASE_CONNECTION=postgresql://user:pass@host:5432/tubesync
# MySQL/MariaDB needs the driver installed first (it is not bundled):
#   apt install -y build-essential default-libmysqlclient-dev pkg-config
#   uv pip install --python /opt/tubesync/.venv/bin/python mysqlclient
# DATABASE_CONNECTION=mysql://user:pass@host:3306/tubesync
EOF

set -a
source /opt/tubesync.env
set +a
cd /opt/tubesync/tubesync
$STD /opt/tubesync/.venv/bin/python manage.py migrate --no-input
$STD /opt/tubesync/.venv/bin/python manage.py compilescss
$STD /opt/tubesync/.venv/bin/python manage.py collectstatic --no-input
msg_ok "Configured TubeSync"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/tubesync.service
[Unit]
Description=TubeSync (gunicorn)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/tubesync/tubesync
EnvironmentFile=/opt/tubesync.env
RuntimeDirectory=tubesync
ExecStart=/opt/tubesync/.venv/bin/gunicorn --config /opt/tubesync/tubesync/tubesync/gunicorn.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/tubesync-worker@.service
[Unit]
Description=TubeSync Huey Worker (%i queue)
After=network.target tubesync.service

[Service]
Type=simple
WorkingDirectory=/opt/tubesync/tubesync
EnvironmentFile=/opt/tubesync.env
ExecStart=/opt/tubesync/.venv/bin/python /opt/tubesync/tubesync/manage.py djangohuey --queue %i
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/tubesync-syslog.service
[Unit]
Description=TubeSync hat-syslog log server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/tubesync/tubesync
EnvironmentFile=/opt/tubesync.env
ExecStart=/opt/tubesync/.venv/bin/hat-syslog-server --log-level INFO --db-enable-archive --db-path /opt/tubesync-config/hat/syslog.db
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now tubesync-syslog tubesync tubesync-worker@database tubesync-worker@network tubesync-worker@limited tubesync-worker@filesystem
msg_ok "Created Services"

msg_info "Configuring Nginx"
# nginx owns port 4848: proxies / to gunicorn, serves downloaded media at
# /media-data/, and proxies /web-logs/ to the hat-syslog web UI (port 23020).
cat <<'EOF' >/etc/nginx/conf.d/tubesync.conf
server {
    listen 4848;
    listen [::]:4848;
    server_name _;
    client_max_body_size 0;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_redirect off;
    }

    location /media-data/ {
        alias /opt/tubesync-downloads/;
    }

    location /web-logs/ {
        proxy_pass http://127.0.0.1:23020/;
        proxy_set_header Host $host;
        proxy_redirect / /web-logs/;
    }

    location /ws {
        proxy_pass http://127.0.0.1:23020/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400s;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
$STD nginx -t
systemctl enable -q nginx
$STD systemctl restart nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
