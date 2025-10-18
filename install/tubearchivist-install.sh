#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Kristian SKov
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.tubearchivist.com/

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get update -y
$STD apt-get install ca-certificates curl
$STD install -m 0755 -d /etc/apt/keyrings
$STD curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
$STD chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

$STD apt-get update -y

$STD apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

msg_ok "Installed Dependencies"

msg_info "Setting up docker compose file"
cat << EOF >docker-compose.yml
services:
  tubearchivist:
    container_name: tubearchivist
    restart: unless-stopped
    image: bbilly1/tubearchivist
    ports:
      - 8000:8000
    volumes:
      - media:/youtube
      - cache:/cache
    environment:
      - ES_URL=http://archivist-es:9200     # needs protocol e.g. http and port
      - REDIS_CON=redis://archivist-redis:6379
      - HOST_UID=1000
      - HOST_GID=1000
      - TA_HOST=http://${IP}:[PORT]$  # set your host name with protocol and port
      - TA_USERNAME=admin           # your initial TA credentials
      - TA_PASSWORD=admin              # your initial TA credentials
      - TA_AUTO_UPDATE_YTDLP=release
      - ELASTIC_PASSWORD=verysecret         # set password for Elasticsearch
      - TZ=Europe/Copenhagen                 # set your time zone
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/health"]
      interval: 2m
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      - archivist-es
      - archivist-redis
  archivist-redis:
    image: redis
    container_name: archivist-redis
    restart: unless-stopped
    expose:
      - "6379"
    volumes:
      - redis:/data
    depends_on:
      - archivist-es
  archivist-es:
    image: bbilly1/tubearchivist-es         # only for amd64, or use official es 8.18.0
    container_name: archivist-es
    restart: unless-stopped
    environment:
      - "ELASTIC_PASSWORD=verysecret"       # matching Elasticsearch password
      - "ES_JAVA_OPTS=-Xms1g -Xmx1g"
      - "xpack.security.enabled=true"
      - "discovery.type=single-node"
      - "path.repo=/usr/share/elasticsearch/data/snapshot"
    volumes:
      - es:/usr/share/elasticsearch/data    # check for permission error when using bind mount, see readme
    expose:
      - "9200"

volumes:
  media:
  cache:
  redis:
  es:
EOF
  
msg_ok "Docker compose file created"

msg_info "Pulling Docker Image"
docker compose pull
msg_ok "Docker image pulled"

msg_info "Starting Tubearchivist"
docker compose up -d
msg_ok "Tubearchivist started"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
