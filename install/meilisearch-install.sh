#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.meilisearch.com/

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
    sudo \
    gnupg \
    mc
msg_ok "Installed Dependencies"

msg_info "Setup ${APPLICATION}"
tmp_file=$(mktemp)
mkdir -p /opt/meilisearch
mkdir -p /opt/meilisearch_data
RELEASE=$(curl -s https://api.github.com/repos/meilisearch/meilisearch/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/meilisearch/meilisearch/releases/download/${RELEASE}/meilisearch-linux-amd64" -O $tmp_file
mv $tmp_file /opt/meilisearch/meilisearch
chmod +x /opt/meilisearch/meilisearch
echo "MEILI_MASTER_KEY=\"$(openssl rand -base64 32)\"" >/opt/meilisearch_data/.env
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

read -p "Do you want add meilisearch-ui? [y/n]: " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    msg_info "Setting up Node.js Repository"
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
    msg_ok "Set up Node.js Repository"

    msg_info "Installing Node.js"
    $STD apt-get update
    $STD apt-get install -y nodejs
    $STD npm install -g pnpm
    msg_ok "Installed Node.js"

    msg_info "Setup ${APPLICATION}-ui"
    tmp_file=$(mktemp)
    tmp_dir=$(mktemp -d)
    mkdir -p /opt/meilisearch-ui
    RELEASE_UI=$(curl -s https://api.github.com/repos/riccox/meilisearch-ui/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    wget -q "https://github.com/riccox/meilisearch-ui/archive/refs/tags/${RELEASE_UI}.zip" -O $tmp_file
    unzip -q "$tmp_file" -d "$tmp_dir"
    mv "$tmp_dir"/*/* /opt/meilisearch-ui/
    cd /opt/meilisearch-ui
    pnpm install
    cat <<EOF > /opt/meilisearch_ui/.env.local
VITE_SINGLETON_MODE=true
VITE_SINGLETON_HOST=http://localhost:7700
VITE_SINGLETON_API_KEY="$(grep 'MEILI_MASTER_KEY' /opt/meilisearch_data/.env | cut -d '"' -f2)"
EOF
cat <<EOF > /etc/systemd/system/meilisearch-ui.service
[Unit]
Description=Meilisearch UI Service
After=network.target meilisearch.service
Requires=meilisearch.service

[Service]
User=root
WorkingDirectory=/opt/meilisearch-ui
ExecStart=/usr/bin/pnpm start
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=meilisearch-ui

[Install]
WantedBy=multi-user.target
EOF

    echo "${RELEASE_UI}" >/opt/${APPLICATION}-ui_version.txt
    msg_ok "Setup ${APPLICATION}-ui"


motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
