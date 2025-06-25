#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Ben Whybrow
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/OpenCut-app/OpenCut

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Dependencies
msg_info "Installing Dependencies"

# APT
$STD apt-get update
$STD apt-get install -y \
    curl \
    unzip \
    git \
    ca-certificates

# Bun
msg_info "Installing Bun"
export BUN_INSTALL=/opt/bun
curl -fsSL https://bun.sh/install | $STD bash
ln -sf /opt/bun/bin/bun /usr/local/bin/bun
ln -sf /opt/bun/bin/bun /usr/local/bin/bunx
msg_ok "Installed Bun"

# Docker and Docker Compose
msg_info "Installing Docker and Docker Compose"
$STD install -m 0755 -d /etc/apt/keyrings
$STD curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
$STD chmod a+r /etc/apt/keyrings/docker.asc
$STD echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
$STD apt-get update
$STD apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
msg_ok "Installed Docker and Docker Compose"

msg_ok "Installed Dependencies"

# Clone Repo
msg_info "Cloning OpenCut Repository"
git clone https://github.com/OpenCut-app/OpenCut.git /opt/OpenCut
cd /opt/OpenCut
msg_ok "Cloned OpenCut Repository"

# Backend Services
msg_info "Setting up Backend Services"
docker compose up -d
msg_ok "Backend Services are running"

# Setup environmental variables
msg_info "Configuring Environmental Variables"
cd /opt/OpenCut/apps/web
cp .env.example .env
msg_ok "Environmental Variables configured"

# Install dependencies
msg_info "Installing OpenCut Dependencies (Patience)"
bun install
msg_ok "OpenCut Dependencies installed"

# Run database migrations
msg_info "Running Database Migrations"
bun run db:push:local
msg_ok "Database Migrations completed"

# Setup service
msg_info "Setup OpenCut Service"
cat <<EOF >/etc/systemd/system/opencut.service
[Unit]
Description=OpenCut
After=network.target docker.service

[Service]
WorkingDirectory=/opt/OpenCut/apps/web
ExecStart=/usr/local/bin/bun run dev
Restart=always
RestartSec=10
User=root
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=NODE_ENV=development

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now opencut
msg_ok "Done Setting Up OpenCut Service"

msg_ok "Installation completed"

motd_ssh
customize
