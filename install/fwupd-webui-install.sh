#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: yuzi-co
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/yuzi-co/fwupd-webui

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
# fwupd brings fwupdtool, which runs the fwupd engine in-process. The fwupd
# daemon and its systemd units arrive in the same package but are never used.
$STD apt install -y \
  fwupd \
  python3 \
  python3-venv \
  git
msg_ok "Installed Dependencies"

msg_info "Setting up fwupd-webui"
$STD git clone --depth 1 https://github.com/yuzi-co/fwupd-webui.git /opt/fwupd-webui/src-checkout
$STD python3 -m venv /opt/fwupd-webui/venv
$STD /opt/fwupd-webui/venv/bin/pip install --upgrade pip
$STD /opt/fwupd-webui/venv/bin/pip install /opt/fwupd-webui/src-checkout
msg_ok "Set up fwupd-webui"

msg_info "Creating Configuration"
mkdir -p /etc/fwupd-webui
cat <<EOF >/etc/fwupd-webui/env
FWUPD_WEBUI_PORT=8099

# Firmware writes are OFF by default. While this is false the flash routes are
# not registered at all. Even when enabled, every flash requires typing the
# device name, and system firmware (BIOS, UEFI capsule, SPI flash) is refused.
FWUPD_WEBUI_ENABLE_FLASHING=false
EOF
chmod 0640 /etc/fwupd-webui/env
msg_ok "Created Configuration"

msg_info "Creating Service"
# Runs as root: device enumeration requires it. The hardening below is what can
# be applied without hiding the hardware this service exists to read.
cat <<EOF >/etc/systemd/system/fwupd-webui.service
[Unit]
Description=fwupd Web UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/fwupd-webui/env
ExecStart=/opt/fwupd-webui/venv/bin/python -m fwupd_webui
Restart=on-failure
RestartSec=5
User=root
NoNewPrivileges=yes
ProtectHome=yes
ProtectHostname=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
SystemCallArchitectures=native
ReadWritePaths=/var/lib/fwupd

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now fwupd-webui
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned"
