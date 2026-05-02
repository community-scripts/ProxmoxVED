#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stephen Chin (steveonjava)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://hermes-agent.nousresearch.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Creating Hermes User"
useradd -m -s /bin/bash hermes
msg_ok "Created Hermes User"

msg_info "Installing Hermes Agent"
$STD setsid --wait env \
  HOME=/home/hermes \
  PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash <(curl -fsSL https://hermes-agent.nousresearch.com/install.sh) --skip-setup --hermes-home /home/hermes/.hermes --dir /home/hermes/.hermes/hermes-agent

if [[ ! -x /home/hermes/.local/bin/hermes ]]; then
  msg_error "Hermes binary not found after installation"
  exit 1
fi

chown -R hermes:hermes /home/hermes
git config --system --add safe.directory /home/hermes/.hermes/hermes-agent 2>/dev/null || true
msg_ok "Installed Hermes Agent"

msg_info "Installing Web Dashboard"
$STD runuser -u hermes -- \
  env HOME=/home/hermes VIRTUAL_ENV=/home/hermes/.hermes/hermes-agent/venv \
  /home/hermes/.local/bin/uv pip install 'hermes-agent[web,pty]'
msg_ok "Installed Web Dashboard"

msg_info "Configuring API Server"
API_SERVER_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
cat <<EOF >/home/hermes/.hermes/.env
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=${API_SERVER_KEY}
HERMES_REDACT_SECRETS=true
EOF
chmod 600 /home/hermes/.hermes/.env
chown hermes:hermes /home/hermes/.hermes/.env
msg_ok "Configured API Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/hermes-gateway.service
[Unit]
Description=Hermes Agent Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=hermes
Group=hermes
UMask=0077
WorkingDirectory=/home/hermes
ExecStart=/home/hermes/.local/bin/hermes gateway run --replace
Environment="HERMES_HOME=/home/hermes/.hermes"
Environment="HOME=/home/hermes"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hermes-gateway
msg_ok "Created Service"

msg_info "Creating Dashboard Service"
cat <<EOF >/etc/systemd/system/hermes-dashboard.service
[Unit]
Description=Hermes Agent Web Dashboard
After=network-online.target hermes-gateway.service
Wants=network-online.target

[Service]
Type=simple
User=hermes
Group=hermes
UMask=0077
WorkingDirectory=/home/hermes
ExecStart=/home/hermes/.local/bin/hermes dashboard --host 127.0.0.1 --port 9119 --no-open
Environment="HERMES_HOME=/home/hermes/.hermes"
Environment="HOME=/home/hermes"
Environment="PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="NODE_OPTIONS=--max-old-space-size=3072"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hermes-dashboard
msg_ok "Created Dashboard Service"

msg_info "Creating Hermes Shim"
cat <<'EOF' >/usr/bin/hermes
#!/bin/bash
cd /home/hermes
exec runuser -u hermes -- /home/hermes/.local/bin/hermes "$@"
EOF
chmod +x /usr/bin/hermes
msg_ok "Created Hermes Shim"

motd_ssh
customize
cleanup_lxc
