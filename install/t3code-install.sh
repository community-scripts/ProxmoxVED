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
  build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

msg_info "Installing T3 Code and Provider CLIs"
$STD npm install -g \
  t3 \
  @openai/codex \
  @anthropic-ai/claude-code \
  @xai-official/grok \
  opencode-ai
msg_ok "Installed T3 Code and Provider CLIs"

fetch_and_deploy_gh_release "gh" "cli/cli" "binary"

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
Environment=T3CODE_TELEMETRY_ENABLED=false
WorkingDirectory=/opt/t3code_data
ExecStart=/usr/bin/t3 serve --host 0.0.0.0 --base-dir /opt/t3code_data
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now t3code
msg_ok "Created Service"

msg_info "Verifying T3 Code Server"
# systemctl enable --now returns once the unit is active, but t3 serve keeps
# initializing for ~1-2s afterwards and only then writes its runtime manifest.
# Confirm it actually came up (and fail loudly if it didn't) before finishing.
for _ in {1..60}; do
  [[ -f /opt/t3code_data/userdata/server-runtime.json ]] && break
  sleep 1
done
if [[ ! -f /opt/t3code_data/userdata/server-runtime.json ]]; then
  msg_error "T3 Code server failed to start"
  exit 1
fi
msg_ok "T3 Code Server Running"

motd_ssh
customize
cleanup_lxc
