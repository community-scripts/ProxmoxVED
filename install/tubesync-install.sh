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
$STD apt install -y ffmpeg
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

msg_info "Configuring TubeSync"
mkdir -p /opt/tubesync-config /opt/tubesync-downloads
# Derive local_settings.py from the upstream container example and point the
# config/downloads directories at persistent paths outside the app directory.
cp /opt/tubesync/tubesync/tubesync/local_settings.py.container /opt/tubesync/tubesync/tubesync/local_settings.py
sed -i "s|CONFIG_BASE_DIR = ROOT_DIR / 'config'|CONFIG_BASE_DIR = Path('/opt/tubesync-config')|" /opt/tubesync/tubesync/tubesync/local_settings.py
sed -i "s|DOWNLOADS_BASE_DIR = ROOT_DIR / 'downloads'|DOWNLOADS_BASE_DIR = Path('/opt/tubesync-downloads')|" /opt/tubesync/tubesync/tubesync/local_settings.py

SECRET_KEY=$(openssl rand -hex 32)
cat <<EOF >/opt/tubesync.env
DJANGO_SECRET_KEY=${SECRET_KEY}
TUBESYNC_HOSTS=*
LISTEN_HOST=0.0.0.0
LISTEN_PORT=4848
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
ExecStart=/opt/tubesync/.venv/bin/gunicorn \\
    --config /opt/tubesync/tubesync/tubesync/gunicorn.py \\
    --chdir /opt/tubesync/tubesync \\
    --user root --group root \\
    --pid /run/tubesync/gunicorn.pid \\
    tubesync.wsgi:application
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

systemctl enable -q --now tubesync tubesync-worker@database tubesync-worker@network tubesync-worker@limited tubesync-worker@filesystem
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
