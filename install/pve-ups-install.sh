#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ffind-dev/pve-ups

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_uv

fetch_and_deploy_gh_release "pve-usv" "ffind-dev/pve-ups" "tarball"

msg_info "Setting up Application"
useradd --system --home /opt/pve-usv --shell /usr/sbin/nologin pveusv
install -d -o pveusv -g pveusv -m 0750 \
  /etc/pve-usv \
  /var/lib/pve-usv \
  /var/lib/pve-usv/agent \
  /var/lib/pve-usv/agent/queue \
  /var/lib/pve-usv/updates
chown -R pveusv:pveusv /opt/pve-usv
cd /opt/pve-usv
$STD uv venv --clear venv
$STD uv pip install --python venv/bin/python .
chmod 0755 deploy/pve-usv-agent.sh
msg_ok "Set up Application"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/pve-usv.service
[Unit]
Description=PVE-UPS - UPS shutdown appliance for Proxmox VE
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pveusv
Group=pveusv
Environment=PVE_USV_CONFIG=/etc/pve-usv/config.yaml
Environment=PVE_USV_DB=/var/lib/pve-usv/events.db
ExecStart=/opt/pve-usv/venv/bin/python -m app.main
WorkingDirectory=/opt/pve-usv
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=/etc/pve-usv /var/lib/pve-usv
ProtectHome=true
LimitNOFILE=4096
MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/pve-usv-agent.service
[Unit]
Description=PVE-UPS deploy agent (privileged update/NTP applier)
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/pve-usv/deploy/pve-usv-agent.sh
EOF
cat <<EOF >/etc/systemd/system/pve-usv-agent.path
[Unit]
Description=PVE-UPS deploy agent trigger (update/NTP queue watch)

[Path]
DirectoryNotEmpty=/var/lib/pve-usv/agent/queue
Unit=pve-usv-agent.service

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/pve-usv-agent.timer
[Unit]
Description=PVE-UPS deploy agent timer (drain update/NTP queue)

[Timer]
OnBootSec=15s
OnUnitActiveSec=20s
Persistent=true
Unit=pve-usv-agent.service

[Install]
WantedBy=timers.target
EOF
systemctl enable -q --now pve-usv pve-usv-agent.path pve-usv-agent.timer
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
