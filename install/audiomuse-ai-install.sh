#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/NeptuneHub/AudioMuse-AI

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
  git \
  ffmpeg \
  libsndfile1 \
  libgomp1 \
  redis-server
systemctl enable -q --now redis-server
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="audiomuse" PG_DB_USER="audiomuse" setup_postgresql_db
UV_PYTHON="3.11" setup_uv

fetch_and_deploy_gh_release "audiomuse-ai" "NeptuneHub/AudioMuse-AI" "tarball"

msg_info "Setting up Python Environment (Patience)"
cd /opt/audiomuse-ai
$STD uv venv --python 3.11 /opt/audiomuse-ai/.venv
$STD uv pip install --python /opt/audiomuse-ai/.venv \
  -r /opt/audiomuse-ai/requirements/common.txt \
  -r /opt/audiomuse-ai/requirements/cpu.txt
msg_ok "Set up Python Environment"

msg_info "Configuring AudioMuse-AI"
mkdir -p /opt/audiomuse-ai_data/models/huggingface /opt/audiomuse-ai_data/cache/numba
AUDIOMUSE_PASSWORD=$(openssl rand -base64 18)
JWT_SECRET=$(openssl rand -hex 32)
API_TOKEN=$(openssl rand -hex 32)
cat <<EOF >/opt/audiomuse-ai_data/audiomuse.env
POSTGRES_USER=audiomuse
POSTGRES_PASSWORD=${PG_DB_PASS}
POSTGRES_DB=audiomuse
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
REDIS_URL=redis://127.0.0.1:6379/0
TZ=UTC
AUTH_ENABLED=true
AUDIOMUSE_USER=admin
AUDIOMUSE_PASSWORD=${AUDIOMUSE_PASSWORD}
JWT_SECRET=${JWT_SECRET}
API_TOKEN=${API_TOKEN}
MEDIASERVER_TYPE=jellyfin
JELLYFIN_URL=http://YOUR_JELLYFIN_IP:8096
JELLYFIN_USER_ID=
JELLYFIN_TOKEN=
AI_MODEL_PROVIDER=NONE
HF_HOME=/opt/audiomuse-ai_data/models/huggingface
XDG_CACHE_HOME=/opt/audiomuse-ai_data/cache
NUMBA_CACHE_DIR=/opt/audiomuse-ai_data/cache/numba
EOF
{
  echo ""
  echo "AudioMuse-AI-Credentials"
  echo "Web UI User: admin"
  echo "Web UI Password: ${AUDIOMUSE_PASSWORD}"
} >>~/audiomuse-ai.creds
msg_ok "Configured AudioMuse-AI"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/audiomuse-ai.service
[Unit]
Description=AudioMuse-AI Web (Flask)
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/audiomuse-ai
EnvironmentFile=/opt/audiomuse-ai_data/audiomuse.env
ExecStart=/opt/audiomuse-ai/.venv/bin/gunicorn flask_app:app --bind 0.0.0.0:8000 --workers 2 --timeout 600
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/audiomuse-ai-worker.service
[Unit]
Description=AudioMuse-AI RQ Worker
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/audiomuse-ai
EnvironmentFile=/opt/audiomuse-ai_data/audiomuse.env
ExecStart=/opt/audiomuse-ai/.venv/bin/python rq_worker.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/audiomuse-ai-worker-high.service
[Unit]
Description=AudioMuse-AI RQ High-Priority Worker
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/audiomuse-ai
EnvironmentFile=/opt/audiomuse-ai_data/audiomuse.env
ExecStart=/opt/audiomuse-ai/.venv/bin/python rq_worker_high_priority.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/audiomuse-ai-janitor.service
[Unit]
Description=AudioMuse-AI RQ Janitor
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/audiomuse-ai
EnvironmentFile=/opt/audiomuse-ai_data/audiomuse.env
ExecStart=/opt/audiomuse-ai/.venv/bin/python rq_janitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now audiomuse-ai audiomuse-ai-worker audiomuse-ai-worker-high audiomuse-ai-janitor
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
