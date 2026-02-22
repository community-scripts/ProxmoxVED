#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thieneret
# License: MIT | https://github.com/thieneret/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/goauthentik/authentik

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
  libffi-dev \
  libxslt-dev \
  zlib1g-dev \
  libpq-dev \
  krb5-multidev \
  libkrb5-dev \
  heimdal-multidev \
  libclang-dev \
  libltdl-dev \
  libpq5 \
  libmaxminddb0 \
  libkrb5-3 \
  libkdb5-10 \
  libkadm5clnt-mit12 \
  libkadm5clnt7t64-heimdal \
  libltdl7 \
  libxslt1.1 \
  python3-dev \
  libxml2-dev \
  libxml2 \
  libxslt1-dev \
  automake \
  autoconf \
  libtool \
  libtool-bin \
  gcc
msg_ok "Installed Dependencies"

AUTHENTIK_VERSION="version/2025.12.4"
NODE_VERSION="24"

fetch_and_deploy_gh_release "xmlsec" "lsh123/xmlsec" "tarball" "latest" "/opt/xmlsec"

msg_info "Setup xmlsec"
cd /opt/xmlsec
$STD ./autogen.sh
$STD make -j $(nproc)
$STD make check
$STD make install
ldconfig
msg_ok "xmlsec installed"

setup_nodejs
setup_go

fetch_and_deploy_gh_release "authentik" "goauthentik/authentik" "tag" "${AUTHENTIK_VERSION}" "/opt/authentik"

msg_info "Setup web"
cd /opt/authentik/web
NODE_ENV="production"
$STD npm install
$STD npm run build
$STD npm run build:sfe
msg_ok "Web installed"

msg_info "Setup go proxy"
cd /opt/authentik
CGO_ENABLED="1"
$STD go mod download
$STD go build -o /opt/authentik/authentik-server ./cmd/server
msg_ok "Go proxy installed"

fetch_and_deploy_gh_release "geoipupdate" "maxmind/geoipupdate" "binary"

cat <<EOF>/usr/local/etc/GeoIP.conf
AccountID ChangeME
LicenseKey ChangeME
EditionIDs GeoLite2-ASN GeoLite2-City GeoLite2-Country
DatabaseDirectory /opt/authentik-data/geoip
RetryFor 5m
Parallelism 1
EOF

cat <<EOF>/tmp/crontab
#39 19 * * 6,4 /usr/bin/geoipupdate -f /usr/local/etc/GeoIP.conf
EOF
crontab /tmp/crontab
rm /tmp/crontab

setup_uv

setup_rust

msg_info "Setup python server"
UV_NO_BINARY_PACKAGE="cryptography lxml python-kadmin-rs xmlsec"
UV_COMPILE_BYTECODE="1"
UV_LINK_MODE="copy"
UV_NATIVE_TLS="1"
RUSTUP_PERMIT_COPY_RENAME="true"
cd /opt/authentik
$STD uv sync --frozen --no-install-project --no-dev
msg_ok "Installed python server"

mkdir -p /opt/authentik-data/{certs,media,geoip,templates}
cp /opt/authentik/authentik/sources/kerberos/krb5.conf /etc/krb5.conf

PG_VERSION="16" setup_postgresql

PG_DB_NAME="authentik" PG_DB_USER="authentik" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

setup_yq

msg_info "Creating authentik config"
mkdir -p /etc/authentik
mv /opt/authentik/authentik/lib/default.yml /etc/authentik/config.yml
yq -i ".secret_key = \"$(openssl rand -base64 128 | tr -dc 'a-zA-Z0-9' | head -c64)\"" /etc/authentik/config.yml
yq -i ".postgresql.password = \"${PG_DB_PASS}\"" /etc/authentik/config.yml
yq -i ".events.context_processors.geoip = \"/opt/authentik-data/geoip/GeoLite2-City.mmdb\"" /etc/authentik/config.yml
yq -i ".events.context_processors.asn = \"/opt/authentik-data/geoip/GeoLite2-ASN.mmdb\"" /etc/authentik/config.yml
yq -i ".blueprints_dir = \"/opt/authentik/blueprints\"" /etc/authentik/config.yml
yq -i ".cert_discovery_dir = \"/opt/authentik-data/certs\"" /etc/authentik/config.yml
yq -i ".email.template_dir = \"/opt/authentik-data/templates\"" /etc/authentik/config.yml
yq -i ".storage.file.path = \"/opt/authentik-data\"" /etc/authentik/config.yml
cp /opt/authentik/tests/GeoLite2-ASN-Test.mmdb /opt/authentik-data/geoip/GeoLite2-ASN.mmdb
cp /opt/authentik/tests/GeoLite2-City-Test.mmdb /opt/authentik-data/geoip/GeoLite2-City.mmdb
$STD useradd -U -s /usr/sbin/nologin -r -M -d /opt/authentik authentik
chown -R authentik:authentik /opt/authentik /opt/authentik-data
cat <<EOF>/etc/default/authentik
TMPDIR=/dev/shm/
UV_LINK_MODE=copy
UV_PYTHON_DOWNLOADS=0
UV_NATIVE_TLS=1
VENV_PATH=/opt/authentik/.venv
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
PATH=/opt/authentik/lifecycle:/opt/authentik/.venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
DJANGO_SETTINGS_MODULE=authentik.root.settings
PROMETHEUS_MULTIPROC_DIR="/tmp/authentik_prometheus_tmp"
EOF
msg_ok "authentik config created"

msg_info "Creating services"
cat <<EOF>/etc/systemd/system/authentik-server.service
[Unit]
Description=authentik Go Server (API Gateway)
After=network.target
Wants=postgresql.service

[Service]
User=authentik
Group=authentik
ExecStartPre=/usr/bin/mkdir -p "\${PROMETHEUS_MULTIPROC_DIR}"
ExecStart=/opt/authentik/authentik-server
WorkingDirectory=/opt/authentik/
Restart=always
RestartSec=5
EnvironmentFile=/etc/default/authentik

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF>/etc/systemd/system/authentik-worker.service
[Unit]
Description=authentik Worker
After=network.target postgresql.service

[Service]
User=authentik
Group=authentik
Type=simple
EnvironmentFile=/etc/default/authentik
ExecStart=/usr/local/bin/uv run python -m manage worker --pid-file /dev/shm/authentik-worker.pid
WorkingDirectory=/opt/authentik
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now authentik-server.service authentik-worker.service
msg_ok "Services created"

echo "${AUTHENTIK_VERSION}" > /opt/authentik_version.txt

motd_ssh
customize
cleanup_lxc
