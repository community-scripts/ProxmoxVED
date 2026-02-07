#!/usr/bin/env bash
# Kener install script for ProxmoxVE container
# Copyright (c) 2021-2026 community-scripts ORG
# Author: danynocz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://kener.ing

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing base dependencies"
$STD apt update
$STD apt install -y ca-certificates curl git openssl lsb-release gnupg
msg_ok "Dependencies installed"

msg_info "Setting up Docker APT repository"
$STD install -m 0755 -d /etc/apt/keyrings
$STD curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
$STD chmod a+r /etc/apt/keyrings/docker.asc

cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: bookworm
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
msg_ok "Docker repository added"

msg_info "Installing Docker Engine"
$STD apt update
$STD apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
msg_ok "Docker installed"

msg_info "Creating Kener directory structure"
mkdir -p /opt/kener/uploads
chown -R root:root /opt/kener
msg_ok "Directory structure ready"

msg_info "Creating .env file"
cat <<EOF > /opt/kener/.env
KENER_SECRET_KEY=$(openssl rand -hex 32)
POSTGRES_USER=kener
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_DB=kener
EOF
msg_ok ".env file created"

HOST_IP=$(hostname -I | awk '{print $1}')

msg_info "Creating Docker Compose file"
cat <<EOF > /opt/kener/docker-compose.yaml
version: "3.8"

services:
  kener:
    image: rajnandan1/kener:latest
    container_name: kener
    environment:
      ORIGIN: http://${HOST_IP}:3000
      TZ: Europe/Prague
      KENER_SECRET_KEY: \${KENER_SECRET_KEY}
      DATABASE_URL: postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}
    ports:
      - "3000:3000"
    volumes:
      - ./uploads:/app/uploads
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

  postgres:
    image: postgres:alpine
    container_name: postgres
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  pgdata:
    name: kener_postgres
EOF
msg_ok "Docker Compose file created"

msg_info "Starting Kener containers"
cd /opt/kener
$STD docker compose up -d
msg_ok "Kener is running"

motd_ssh
customize
cleanup_lxc
