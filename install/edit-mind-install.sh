#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/IliasHad/edit-mind

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
  cmake \
  redis-server \
  nginx \
  python3 \
  python3-dev \
  python3-venv \
  python3-pip \
  libgomp1 \
  libglib2.0-0 \
  libgl1 \
  libsm6 \
  libxext6 \
  libxrender1 \
  openssl
msg_ok "Installed Dependencies"

setup_ffmpeg
PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="editmind" PG_DB_USER="editmind" setup_postgresql_db
NODE_VERSION="22" setup_nodejs

msg_info "Installing pnpm"
$STD npm install -g pnpm@10
msg_ok "Installed pnpm"

fetch_and_deploy_gh_release "edit-mind" "IliasHad/edit-mind" "tarball"

msg_info "Installing Application Dependencies"
cd /opt/edit-mind
$STD pnpm install --prefer-frozen-lockfile
$STD pnpm --filter prisma generate
msg_ok "Installed Application Dependencies"

msg_info "Building Application"
$STD pnpm run build:web
$STD pnpm rebuild @tailwindcss/oxide rollup onnxruntime-node
$STD pnpm run build:background-jobs
msg_ok "Built Application"

msg_info "Setting up Python ML Environment"
python3 -m venv /opt/edit-mind/.venv
$STD /opt/edit-mind/.venv/bin/pip install --upgrade pip
$STD /opt/edit-mind/.venv/bin/pip install --no-cache-dir -r /opt/edit-mind/python/requirements.txt
msg_ok "Set up Python ML Environment"

msg_info "Setting up ChromaDB"
$STD /opt/edit-mind/.venv/bin/pip install --no-cache-dir chromadb
msg_ok "Set up ChromaDB"

msg_info "Configuring Application"
SESSION_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
mkdir -p /opt/edit-mind/.data /opt/edit-mind/ml-models
cat <<EOF >/opt/edit-mind/.env
SESSION_SECRET=${SESSION_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
HOST_MEDIA_PATH=/opt/edit-mind/media
OLLAMA_MODEL=qwen2.5:7b-instruct
USE_OLLAMA_MODEL=false
OLLAMA_HOST=
OLLAMA_PORT=
GEMINI_API_KEY=
USE_GEMINI=false
PORT=3745
BACKGROUND_JOBS_PORT=4000
ML_PORT=8765
REDIS_PORT=6379
POSTGRES_PORT=5432
CHROMA_PORT=8000
EOF
cat <<EOF >/opt/edit-mind/.env.system
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
REDIS_HOST=127.0.0.1
CHROMA_HOST=127.0.0.1
IS_PERSISTENT=TRUE
ML_HOST=127.0.0.1
PROCESSED_VIDEOS_DIR=/opt/edit-mind/.data
THUMBNAILS_PATH=/opt/edit-mind/.data/.thumbnails
STITCHED_VIDEOS_DIR=/opt/edit-mind/.data/.stitched-videos
FACES_DIR=/opt/edit-mind/.data/.faces
UNKNOWN_FACES_DIR=/opt/edit-mind/.data/.unknown_faces
KNOWN_FACES_FILE=/opt/edit-mind/.data/.faces.json
KNOWN_FACES_FILE_LOADED=/opt/edit-mind/.data/.known_faces.json
BACKGROUND_JOBS_URL=http://127.0.0.1:4000
NODE_ENV=production
ANONYMIZED_TELEMETRY=FALSE
WEB_APP_URL=http://127.0.0.1:3745
EOF
mkdir -p /opt/edit-mind/media
set -a && source /opt/edit-mind/.env && source /opt/edit-mind/.env.system && set +a
$STD pnpm --filter prisma migrate:deploy
$STD pnpm --filter db seed
msg_ok "Configured Application"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/edit-mind-chroma.service
[Unit]
Description=Edit-Mind ChromaDB
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
Environment=IS_PERSISTENT=TRUE
ExecStart=/opt/edit-mind/.venv/bin/chroma run --host 127.0.0.1 --port 8000 --path /opt/edit-mind/.data/chroma
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/edit-mind-ml.service
[Unit]
Description=Edit-Mind ML Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
EnvironmentFile=/opt/edit-mind/.env
EnvironmentFile=/opt/edit-mind/.env.system
Environment=YOLO_CONFIG_DIR=/opt/edit-mind/ml-models/ultralytics
Environment=DEEPFACE_HOME=/opt/edit-mind/ml-models/deepface
Environment=TRANSCRIPTION_MODEL_CACHE=/opt/edit-mind/ml-models/whisper
Environment=TORCH_HOME=/opt/edit-mind/ml-models/torch
Environment=HF_HOME=/opt/edit-mind/ml-models/huggingface
ExecStart=/opt/edit-mind/.venv/bin/python /opt/edit-mind/python/main.py --host 0.0.0.0 --port 8765
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/edit-mind-jobs.service
[Unit]
Description=Edit-Mind Background Jobs
After=network.target postgresql.service redis-server.service edit-mind-chroma.service edit-mind-ml.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
EnvironmentFile=/opt/edit-mind/.env
EnvironmentFile=/opt/edit-mind/.env.system
ExecStart=/usr/bin/pnpm --filter background-jobs start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/edit-mind-web.service
[Unit]
Description=Edit-Mind Web Application
After=network.target postgresql.service redis-server.service edit-mind-chroma.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/edit-mind
EnvironmentFile=/opt/edit-mind/.env
EnvironmentFile=/opt/edit-mind/.env.system
ExecStart=/usr/bin/pnpm --filter web start --host 0.0.0.0 --port 3745
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now edit-mind-chroma
systemctl enable -q --now edit-mind-ml
systemctl enable -q --now edit-mind-jobs
systemctl enable -q --now edit-mind-web
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
