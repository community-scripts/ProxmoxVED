#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck / Community
# Author: Community Contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/imputnet/cobalt

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  ca-certificates \
  gnupg \
  lsb-release
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
$STD sh <(curl -sSL https://get.docker.com)
msg_ok "Installed Docker"

msg_info "Pulling Cobalt Docker Images"
mkdir -p /opt/cobalt
cd /opt/cobalt
cat > docker-compose.yml <<'EOF'
services:
  cobalt-api:
    image: ghcr.io/imputnet/cobalt:latest
    container_name: cobalt_api
    restart: unless-stopped
    ports:
      - "9000:9000"
    environment:
      - API_URL=http://localhost:9000/
      - BIND_ADDRESS=0.0.0.0:9000

  cobalt-web:
    image: ghcr.io/imputnet/cobalt-web:latest
    container_name: cobalt_web
    restart: unless-stopped
    ports:
      - "8000:80"
    environment:
      - API_URL=http://cobalt-api:9000/
    depends_on:
      - cobalt-api
EOF
$STD docker compose pull
msg_ok "Pulled Cobalt Docker Images"

msg_info "Starting Cobalt Services"
$STD docker compose up -d
msg_ok "Started Cobalt Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
