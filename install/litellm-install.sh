#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Authors: MickLesk, tremor021
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

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
  python3-dev \
  libpq-dev
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="litellm" PG_DB_USER="litellm" setup_postgresql_db
PYTHON_VERSION="3.12" USE_UVX="YES" setup_uv

fetch_and_deploy_gh_release "litellm" "BerriAI/litellm" "tarball" "latest" "/opt/litellm"

msg_info "Installing LiteLLM (Patience)"
cd /opt/litellm
$STD uv venv .venv
$STD uv pip install --python .venv/bin/python prisma
$STD uv pip install --python .venv/bin/python -e ".[proxy]"
msg_ok "Installed LiteLLM"

msg_info "Configuring LiteLLM"
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
LITELLM_SALT_KEY="sk-$(openssl rand -hex 16)"
DATABASE_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}"

cat <<EOF >/opt/litellm/litellm.yaml
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${DATABASE_URL}
  store_model_in_db: true
litellm_settings:
  salt_key: ${LITELLM_SALT_KEY}
EOF

export DATABASE_URL
export PATH="/opt/litellm/.venv/bin:${PATH}"
$STD .venv/bin/prisma generate --schema=/opt/litellm/schema.prisma
$STD .venv/bin/litellm --config /opt/litellm/litellm.yaml --use_prisma_db_push --skip_server_startup
msg_ok "Configured LiteLLM"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/litellm.service
[Unit]
Description=LiteLLM Proxy
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/litellm
Environment=DATABASE_URL=${DATABASE_URL}
ExecStart=/opt/litellm/.venv/bin/litellm --config /opt/litellm/litellm.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now litellm
msg_ok "Created Service"


cat <<EOF >~/litellm.creds
LiteLLM Credentials
URL: http://${LOCAL_IP}:4000
Master Key: ${LITELLM_MASTER_KEY}
Salt Key: ${LITELLM_SALT_KEY}
Postgres Password: ${PG_DB_PASS}

Note: LITELLM_SALT_KEY cannot be changed after adding models to the proxy.
EOF
chmod 600 ~/litellm.creds
msg_ok "Saved credentials to ~/litellm.creds"

motd_ssh
customize
cleanup_lxc
