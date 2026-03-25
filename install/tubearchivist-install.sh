#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/tubearchivist/tubearchivist

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
  redis-server \
  atomicparsley \
  python3-dev \
  libldap2-dev \
  libsasl2-dev \
  libssl-dev \
  ffmpeg
msg_ok "Installed Dependencies"

UV_PYTHON="3.13" setup_uv
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "deno" "denoland/deno" "prebuild" "latest" "/usr/local/bin" "deno-x86_64-unknown-linux-gnu.zip"

msg_info "Installing ElasticSearch"
setup_deb822_repo "elastic-8.x" "https://artifacts.elastic.co/GPG-KEY-elasticsearch" "https://artifacts.elastic.co/packages/8.x/apt" "stable" "main"
ES_JAVA_OPTS="-Xms1g -Xmx1g" $STD apt install -y elasticsearch
msg_ok "Installed ElasticSearch"

msg_info "Configuring ElasticSearch"
cat <<EOF >/etc/elasticsearch/elasticsearch.yml
cluster.name: tubearchivist
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
path.repo: ["/var/lib/elasticsearch/snapshot"]
network.host: 127.0.0.1
xpack.security.enabled: false
xpack.security.transport.ssl.enabled: false
xpack.security.http.ssl.enabled: false
EOF
mkdir -p /var/lib/elasticsearch/snapshot
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch/snapshot
cat <<EOF >/etc/elasticsearch/jvm.options.d/heap.options
-Xms1g
-Xmx1g
EOF
sysctl -w vm.max_map_count=262144 2>/dev/null || true
cat <<EOF >/etc/sysctl.d/99-elasticsearch.conf
vm.max_map_count=262144
EOF
systemctl enable -q --now elasticsearch
msg_ok "Configured ElasticSearch"

fetch_and_deploy_gh_release "tubearchivist" "tubearchivist/tubearchivist" "tarball" "latest" "/opt/tubearchivist"

msg_info "Building Frontend"
cd /opt/tubearchivist/frontend
$STD npm install
$STD npm run build:deploy
mkdir -p /opt/tubearchivist/backend/static
cp -r /opt/tubearchivist/frontend/dist/* /opt/tubearchivist/backend/static/
msg_ok "Built Frontend"

msg_info "Setting up Tube Archivist"
cp /opt/tubearchivist/docker_assets/backend_start.py /opt/tubearchivist/backend/
$STD uv venv /opt/tubearchivist/.venv
$STD uv pip install --python /opt/tubearchivist/.venv/bin/python -r /opt/tubearchivist/backend/requirements.txt
if [[ -f /opt/tubearchivist/backend/requirements.plugins.txt ]]; then
  mkdir -p /opt/yt_plugins/bgutil
  $STD uv pip install --python /opt/tubearchivist/.venv/bin/python --target /opt/yt_plugins/bgutil -r /opt/tubearchivist/backend/requirements.plugins.txt
fi
TA_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
ES_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
cat <<EOF >/opt/tubearchivist/.env
TA_HOST=http://${LOCAL_IP}:8080
TA_USERNAME=admin
TA_PASSWORD=${TA_PASSWORD}
TA_BACKEND_PORT=8080
ELASTIC_PASSWORD=${ES_PASSWORD}
REDIS_CON=redis://localhost:6379
ES_URL=http://localhost:9200
TZ=UTC
PYTHONUNBUFFERED=1
YTDLP_PLUGIN_DIRS=/opt/yt_plugins
EOF
{
  echo "Tube Archivist Credentials"
  echo "=========================="
  echo "Username: admin"
  echo "Password: ${TA_PASSWORD}"
  echo "Elasticsearch Password: ${ES_PASSWORD}"
} >~/tubearchivist.creds
$STD systemctl enable --now redis-server
msg_ok "Set up Tube Archivist"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/tubearchivist.service
[Unit]
Description=Tube Archivist
After=network.target elasticsearch.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/tubearchivist/backend
EnvironmentFile=/opt/tubearchivist/.env
Environment=PATH=/opt/tubearchivist/.venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/tubearchivist/.venv/bin/python backend_start.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now tubearchivist
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
