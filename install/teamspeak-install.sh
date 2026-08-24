#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nicolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.teamspeak.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

TS_URL=$(curl -fsSL "https://www.teamspeak.com/en/downloads/" | grep -oE 'https://[^"]*teamspeak3-server_linux_amd64-[0-9.]+\.tar\.bz2' | head -1)
TS_VERSION=$(echo "$TS_URL" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

msg_info "Installing TeamSpeak"
mkdir -p /opt/teamspeak
curl -fsSL "$TS_URL" | tar -xjf - -C /opt/teamspeak --strip-components=1
echo "${TS_VERSION}" >~/.teamspeak
msg_ok "Installed TeamSpeak"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/teamspeak.service
[Unit]
Description=TeamSpeak Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/teamspeak
ExecStart=/opt/teamspeak/ts3server license_accepted=1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now teamspeak
msg_ok "Created Service"

msg_info "Waiting for Initial Startup"
LOGFILE=""
for i in $(seq 1 20); do
  LOGFILE=$(grep -l "privilege key" /opt/teamspeak/logs/ts3server_*.log 2>/dev/null | tail -1 || true)
  if [[ -n "$LOGFILE" ]]; then
    break
  fi
  sleep 1
done
msg_ok "Started"

msg_info "Saving Credentials"
{ grep -A2 "privilege key" "$LOGFILE" 2>/dev/null || true; } >~/teamspeak.creds
msg_ok "Saved Credentials"

motd_ssh
customize
cleanup_lxc
