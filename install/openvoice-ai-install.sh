#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nik Pottbecker (nikpottbecker)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nikpottbecker/openvoice-ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  asterisk \
  ffmpeg \
  python3 \
  python3-pip \
  python3-venv \
  rsync \
  sox \
  unzip
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "openvoice-ai" "nikpottbecker/openvoice-ai" "tarball" "latest" "/opt/phone-agent"

msg_info "Setting up Application"
cd /opt/phone-agent
mkdir -p logs recordings transcripts config models/piper agi-bin /var/lib/asterisk/sounds/phone-agent
$STD python3 -m venv .venv
$STD .venv/bin/pip install --upgrade pip wheel
$STD .venv/bin/pip install -r requirements.txt
cp -n .env.example .env
chmod 0640 .env
cat <<EOF >/opt/phone-agent/agi-bin/phone-agent-agi
#!/usr/bin/env bash
cd /opt/phone-agent
export PYTHONPATH=/opt/phone-agent/src
exec /opt/phone-agent/.venv/bin/python -m phone_agent.agi_entrypoint
EOF
chmod 0755 /opt/phone-agent/agi-bin/phone-agent-agi
msg_ok "Set up Application"

msg_info "Creating Services"
install -m 0644 systemd/phone-agent-health.service /etc/systemd/system/phone-agent-health.service
install -m 0644 systemd/phone-agent-health.timer /etc/systemd/system/phone-agent-health.timer
install -m 0644 systemd/phone-agent-dashboard.service /etc/systemd/system/phone-agent-dashboard.service
systemctl enable -q --now asterisk
systemctl enable -q --now phone-agent-dashboard
systemctl enable -q --now phone-agent-health.timer
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
