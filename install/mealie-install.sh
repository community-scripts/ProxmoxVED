#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://mealie.io

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git
msg_ok "Installed Dependencies"

#fetch_and_deploy_gh_release "mealie" "mealie-recipes/mealie" "tarball" "latest" "/opt/mealie" - deactivated for now

PYTHON_VERSION="3.12" setup_uv
POSTGRES_VERSION="16" setup_postgresql
NODE_MODULE="yarn" NODE_VERSION="20" setup_nodejs

msg_info "Get Mealie Repository"
cd /opt
git clone https://github.com/mealie-recipes/mealie
msg_ok "Get Mealie Repository"

msg_info "Building Frontend"
cd /opt/mealie/frontend
yarn install --prefer-offline --frozen-lockfile --non-interactive --production=false --network-timeout 1000000
yarn generate
msg_ok "Built Frontend"

msg_info "Preparing Backend (Poetry)"
$STD uv venv /opt/mealie/.venv
$STD /opt/mealie/.venv/bin/python -m uv pip install -r requirements.txt
cd /opt/mealie
/opt/mealie/.venv/bin/uv pip install poetry==2.0.1
/opt/mealie/.venv/bin/poetry self add "poetry-plugin-export>=1.9"
msg_ok "Prepared Poetry"

msg_info "Building Mealie Backend Wheel"
cd /opt/mealie
/opt/mealie/.venv/bin/poetry build --output dist

MEALIE_VERSION=$(/opt/mealie/.venv/bin/poetry version --short)
/opt/mealie/.venv/bin/poetry export --only=main --extras=pgsql --output=dist/requirements.txt
echo "mealie[pgsql]==$MEALIE_VERSION \\" >>dist/requirements.txt
/opt/mealie/.venv/bin/poetry run pip hash dist/mealie-$MEALIE_VERSION*.whl | tail -n1 | tr -d '\n' >>dist/requirements.txt
echo " \\" >>dist/requirements.txt
/opt/mealie/.venv/bin/poetry run pip hash dist/mealie-$MEALIE_VERSION*.tar.gz | tail -n1 >>dist/requirements.txt
msg_ok "Built Wheel + Requirements"

msg_info "Installing Mealie via uv"
cd /opt/mealie
/opt/mealie/.venv/bin/uv pip install --require-hashes -r dist/requirements.txt --find-links dist
msg_ok "Installed Mealie"

msg_info "Downloading NLTK Data"
mkdir -p /nltk_data/
/opt/mealie/.venv/bin/python -m nltk.downloader -d /nltk_data averaged_perceptron_tagger_eng
msg_ok "Downloaded NLTK Data"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mealie.service
[Unit]
Description=Mealie Server
After=network.target postgresql.service

[Service]
User=root
WorkingDirectory=/opt/mealie
ExecStart=/opt/mealie/.venv/bin/python -m mealie
Restart=always
Environment=HOST=0.0.0.0
Environment=PORT=9000
Environment=DB_ENGINE=postgres
Environment=POSTGRES_SERVER=localhost
Environment=POSTGRES_PORT=5432
Environment=POSTGRES_USER=mealie
Environment=POSTGRES_PASSWORD=mealie
Environment=POSTGRES_DB=mealie
Environment=NLTK_DATA=/nltk_data

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mealie
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
