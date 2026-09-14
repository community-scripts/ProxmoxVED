#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/koala73/worldmonitor

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  redis-server \
  nginx
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "worldmonitor" "koala73/worldmonitor" "tarball" "latest" "/opt/worldmonitor"

msg_info "Building World Monitor (Patience)"
cd /opt/worldmonitor
export NODE_OPTIONS="--max-old-space-size=3072"
$STD npm ci --ignore-scripts
$STD npm ci --prefix scripts --omit=dev --omit=optional --ignore-scripts
$STD npm install --prefix docker redis@4
$STD node docker/build-handlers.mjs
$STD npm run build:crawlable-corpus
$STD npm run build:content-corpus
$STD npx tsc
$STD npx vite build
msg_ok "Built World Monitor"

msg_info "Reclaiming Disk Space"
rm -rf /opt/worldmonitor/node_modules
cp /opt/worldmonitor/docker/runtime-package.json /opt/worldmonitor/package.json
cp /opt/worldmonitor/docker/runtime-package-lock.json /opt/worldmonitor/package-lock.json
$STD npm ci --omit=dev --omit=optional --ignore-scripts
msg_ok "Reclaimed Disk Space"

msg_info "Configuring Redis"
REDIS_PASSWORD=$(openssl rand -hex 32)
cat <<EOF >>/etc/redis/redis.conf
requirepass ${REDIS_PASSWORD}
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF
systemctl enable -q redis-server
systemctl restart redis-server
msg_ok "Configured Redis"

msg_info "Configuring World Monitor"
REDIS_TOKEN=$(openssl rand -hex 32)
RELAY_SHARED_SECRET=$(openssl rand -hex 32)
LOCAL_API_TOKEN=$(openssl rand -hex 32)
cat <<EOF >/opt/worldmonitor/.env
LOCAL_API_PORT=46123
LOCAL_API_MODE=docker
LOCAL_API_CLOUD_FALLBACK=false
LOCAL_API_TOKEN=${LOCAL_API_TOKEN}
UPSTASH_REDIS_REST_URL=http://127.0.0.1:8079
UPSTASH_REDIS_REST_TOKEN=${REDIS_TOKEN}
UPSTASH_ALLOW_INSECURE_HTTP=true
WS_RELAY_URL=http://127.0.0.1:3004
RELAY_SHARED_SECRET=${RELAY_SHARED_SECRET}
RELAY_AUTH_HEADER=x-relay-key
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_TOKEN=${REDIS_TOKEN}
GROQ_API_KEY=
OPENROUTER_API_KEY=
FINNHUB_API_KEY=
FRED_API_KEY=
EIA_API_KEY=
AISSTREAM_API_KEY=
NASA_FIRMS_API_KEY=
ACLED_EMAIL=
ACLED_PASSWORD=
CLOUDFLARE_API_TOKEN=
LLM_API_URL=
LLM_API_KEY=
LLM_MODEL=
EOF
chmod 600 /opt/worldmonitor/.env
msg_ok "Configured World Monitor"

msg_info "Creating Redis REST Proxy Service"
cat <<EOF >/etc/systemd/system/worldmonitor-redis-rest.service
[Unit]
Description=World Monitor Redis REST Proxy
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/worldmonitor/docker
Environment=PORT=8079
Environment=SRH_TOKEN=${REDIS_TOKEN}
Environment=SRH_CONNECTION_STRING=redis://:${REDIS_PASSWORD}@127.0.0.1:6379
ExecStart=/usr/bin/node /opt/worldmonitor/docker/redis-rest-proxy.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now worldmonitor-redis-rest
msg_ok "Created Redis REST Proxy Service"

msg_info "Creating AIS Relay Service"
cat <<EOF >/etc/systemd/system/worldmonitor-ais-relay.service
[Unit]
Description=World Monitor AIS Relay
After=network.target worldmonitor-redis-rest.service
Wants=worldmonitor-redis-rest.service

[Service]
Type=simple
WorkingDirectory=/opt/worldmonitor/scripts
EnvironmentFile=/opt/worldmonitor/.env
Environment=PORT=3004
ExecStart=/usr/bin/node /opt/worldmonitor/scripts/ais-relay.cjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now worldmonitor-ais-relay
msg_ok "Created AIS Relay Service"

msg_info "Creating World Monitor Service"
cat <<EOF >/etc/systemd/system/worldmonitor.service
[Unit]
Description=World Monitor API
After=network.target worldmonitor-redis-rest.service worldmonitor-ais-relay.service
Wants=worldmonitor-redis-rest.service worldmonitor-ais-relay.service

[Service]
Type=simple
WorkingDirectory=/opt/worldmonitor
EnvironmentFile=/opt/worldmonitor/.env
ExecStart=/usr/bin/node /opt/worldmonitor/src-tauri/sidecar/local-api-server.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now worldmonitor
msg_ok "Created World Monitor Service"

msg_info "Configuring Web Server"
cat <<EOF >/etc/nginx/conf.d/worldmonitor.conf
server {
    listen 8080;
    root /opt/worldmonitor/dist;
    index dashboard.html;

    location /assets/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files \$uri =404;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:46123;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Origin http://localhost;
        proxy_set_header X-WorldMonitor-Local-Token "${LOCAL_API_TOKEN}";
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }

    location / {
        try_files \$uri \$uri/ /dashboard.html;
    }
}
EOF
systemctl restart nginx
msg_ok "Configured Web Server"

motd_ssh
customize
cleanup_lxc
