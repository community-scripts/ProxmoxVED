#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/NousResearch/hermes-agent

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  build-essential
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

fetch_and_deploy_gh_release "hermes-agent" "NousResearch/hermes-agent" "tarball"

msg_info "Installing Python Dependencies"
cd /opt/hermes-agent
$STD uv venv .venv --python 3.12
$STD uv pip install -e ".[all]"
msg_ok "Installed Python Dependencies"

msg_info "Creating Configuration Directory"
mkdir -p /root/.hermes
mkdir -p /opt/hermes-agent/data
msg_ok "Created Configuration Directory"

msg_info "Creating Environment File"
cat <<EOF >/opt/hermes-agent/.env
# Hermes Agent Configuration
# Add your LLM provider API keys below

# OpenAI (optional)
# OPENAI_API_KEY=sk-...

# OpenRouter (optional)
# OPENROUTER_API_KEY=sk-or-...

# Nous Portal (optional)
# NOUS_API_KEY=...

# Server configuration
HERMES_HOST=0.0.0.0
HERMES_PORT=8000
EOF
msg_ok "Created Environment File"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/hermes-agent.service
[Unit]
Description=Hermes Agent - Self-improving AI Agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/hermes-agent
EnvironmentFile=/opt/hermes-agent/.env
ExecStart=/opt/hermes-agent/.venv/bin/hermes gateway
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hermes-agent
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc