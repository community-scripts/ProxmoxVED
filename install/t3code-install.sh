#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: lukdz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pingdotgg/t3code

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
  build-essential \
  python3
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Installing T3 Code and Provider CLIs"
$STD npm install -g \
  t3 \
  @openai/codex \
  @anthropic-ai/claude-code \
  opencode-ai
msg_ok "Installed T3 Code and Provider CLIs"

# GitHub CLI (source control provider)
fetch_and_deploy_gh_release "gh" "cli/cli" "binary"

# GitLab CLI (source control provider)
GITLAB_URL="https://gitlab.com" fetch_and_deploy_gl_release \
  "glab" \
  "gitlab-org/cli" \
  "binary"

# Azure CLI + DevOps extension (source control provider)
setup_deb822_repo \
  "azure-cli" \
  "https://packages.microsoft.com/keys/microsoft.asc" \
  "https://packages.microsoft.com/repos/azure-cli" \
  "$(get_os_info codename)" \
  "main"

msg_info "Installing Azure CLI"
$STD apt install -y azure-cli
$STD az extension add --name azure-devops
msg_ok "Installed Azure CLI"

msg_info "Creating Service"
mkdir -p /opt/t3code_data
cat <<EOF >/etc/systemd/system/t3code.service
[Unit]
Description=T3 Code Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=T3_BASE_DIR=/opt/t3code_data
WorkingDirectory=/opt/t3code_data
ExecStart=/usr/bin/t3 serve --host 0.0.0.0 --base-dir /opt/t3code_data
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now t3code
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
