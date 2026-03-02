#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ChatGPT
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/samanhappy/mcphub | Docs: https://docs.mcphubx.com/

if [[ -z "$FUNCTIONS_FILE_PATH" ]]; then
  echo "This script is not intended to run directly."
  echo "Use the CT entrypoint instead: ct/mcphub.sh"
  exit 1
fi

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs

msg_info "Installing MCPHub"
$STD npm install -g @samanhappy/mcphub
msg_ok "Installed MCPHub"

msg_info "Creating Default Configuration"
mkdir -p /opt/mcphub
cat <<EOF >/opt/mcphub/mcp_settings.json
{
  "mcpServers": {
    "time": {
      "command": "npx",
      "args": ["-y", "time-mcp"]
    }
  }
}
EOF
msg_ok "Created Default Configuration"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mcphub.service
[Unit]
Description=MCPHub
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/mcphub
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=MCPHUB_SETTING_PATH=/opt/mcphub/mcp_settings.json
ExecStart=mcphub
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mcphub
msg_ok "Created Service"

msg_info "Configuring Console Auto-Login"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat <<EOF >/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF

mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
cat <<EOF >/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF

systemctl daemon-reload
systemctl restart getty@tty1.service 2>/dev/null || true
systemctl restart serial-getty@ttyS0.service 2>/dev/null || true
msg_ok "Configured Console Auto-Login"

motd_ssh
customize
cleanup_lxc
