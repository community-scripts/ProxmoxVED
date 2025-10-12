#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck
# Co-Author: havardthom
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openwebui.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    ffmpeg
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y --no-install-recommends \
    python3 \
    python3-pip
msg_ok "Setup Python3"

setup_nodejs

msg_info "Installing Open WebUI (Patience)"
fetch_and_deploy_gh_release "open-webui/open-webui"
cd /opt/openwebui/backend
$STD pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
$STD pip3 install -r requirements.txt -U
cd /opt/openwebui
cat <<EOF >/opt/openwebui/.env
# Ollama URL for the backend to connect
# The path '/ollama' will be redirected to the specified backend URL
OLLAMA_BASE_URL=http://0.0.0.0:11434
OPENAI_API_BASE_URL=''
OPENAI_API_KEY=''
# AUTOMATIC1111_BASE_URL="http://localhost:7860"
# DO NOT TRACK
SCARF_NO_ANALYTICS=true
DO_NOT_TRACK=true
ANONYMIZED_TELEMETRY=false
ENV=prod
ENABLE_OLLAMA_API=false
EOF
$STD npm install
export NODE_OPTIONS="--max-old-space-size=3584"
sed -i "s/git rev-parse HEAD/openssl rand -hex 20/g" /opt/openwebui/svelte.config.js
$STD npm run build
msg_ok "Installed Open WebUI"

read -r -p "${TAB3}Would you like to add Ollama? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Installing Ollama"
    curl -fsSLO https://ollama.com/download/ollama-linux-amd64.tgz
    tar -C /usr -xzf ollama-linux-amd64.tgz
    rm -rf ollama-linux-amd64.tgz
    cat <<EOF >/etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
Type=exec
ExecStart=/usr/bin/ollama serve
Environment=HOME=$HOME
Environment=OLLAMA_HOST=0.0.0.0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now ollama
    sed -i 's/ENABLE_OLLAMA_API=false/ENABLE_OLLAMA_API=true/g' /opt/openwebui/.env
    msg_ok "Installed Ollama"
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/open-webui.service
[Unit]
Description=Open WebUI Service
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/openwebui
EnvironmentFile=/opt/openwebui/.env
ExecStart=/opt/openwebui/backend/start.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now open-webui
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
