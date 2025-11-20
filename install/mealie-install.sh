#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://mealie.io

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
  libpq-dev \
  libwebp-dev \
  libsasl2-dev \
  libldap2-dev \
  libssl-dev
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
POSTGRES_VERSION="16" setup_postgresql
NODE_MODULE="yarn" NODE_VERSION="20" setup_nodejs

fetch_and_deploy_gh_release "mealie" "mealie-recipes/mealie" "tarball" "latest" "/opt/mealie"

PG_DB_NAME="mealie_db" PG_DB_USER="mealie_user" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

msg_info "Setting up uv environment"
cd /opt/mealie
$STD uv sync --frozen
msg_ok "Set up uv environment"

msg_info "Building Frontend"
export NUXT_TELEMETRY_DISABLED=1
cd /opt/mealie/frontend
$STD yarn install --prefer-offline --frozen-lockfile --non-interactive --production=false --network-timeout 1000000
$STD yarn generate
msg_ok "Built Frontend"

msg_info "Copying Built Frontend into Backend Package"
cp -r /opt/mealie/frontend/dist /opt/mealie/mealie/frontend
msg_ok "Copied Frontend"

msg_info "Downloading NLTK Data"
mkdir -p /nltk_data/
$STD python -m nltk.downloader -d /nltk_data averaged_perceptron_tagger_eng
msg_ok "Downloaded NLTK Data"

msg_info "Writing Environment File"
cat <<EOF >/opt/mealie/mealie.env
HOST=0.0.0.0
PORT=9000
DB_ENGINE=postgres
POSTGRES_SERVER=localhost
POSTGRES_PORT=5432
POSTGRES_USER=${PG_DB_USER}
POSTGRES_PASSWORD=${PG_DB_PASS}
POSTGRES_DB=${PG_DB_NAME}
NLTK_DATA=/nltk_data
PRODUCTION=true
STATIC_FILES=/opt/mealie/frontend/dist
EOF
msg_ok "Wrote Environment File"

msg_info "Creating Start Script"
cat <<'EOF' >/opt/mealie/start.sh
#!/bin/bash
set -a
source /opt/mealie/mealie.env
set +a
cd /opt/mealie
exec uv run mealie
EOF
chmod +x /opt/mealie/start.sh
msg_ok "Created Start Script"

msg_info "Creating Systemd Service"
cat <<EOF >/etc/systemd/system/mealie.service
[Unit]
Description=Mealie Backend Server
After=network.target postgresql.service

[Service]
User=root
WorkingDirectory=/opt/mealie
ExecStart=/opt/mealie/start.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mealie
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
