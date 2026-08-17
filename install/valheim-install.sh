#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jasmin Härkönen (jasaspi)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.valheimgame.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  lib32gcc-s1 \
  lib32stdc++6 \
  libatomic1 \
  libpulse0
msg_ok "Installed Dependencies"

if [[ -z "${var_server_name:-}" ]]; then
  read -rp "${TAB3}Server name: " var_server_name
fi
var_server_name="${var_server_name:-Valheim Server}"

if [[ -z "${var_world_name:-}" ]]; then
  read -rp "${TAB3}World name: " var_world_name
fi
var_world_name="${var_world_name:-Dedicated}"

if [[ -z "${var_server_password:-}" ]]; then
  read -rp "${TAB3}Server password (min 5 chars, empty = generate): " var_server_password
fi
var_server_password="${var_server_password:-$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 10)}"
if [[ ${#var_server_password} -lt 5 ]]; then
  msg_error "Server password must be at least 5 characters."
  exit 1
fi

if [[ -z "${var_crossplay:-}" ]]; then
  read -rp "${TAB3}Enable crossplay? (y/N): " var_crossplay
fi

msg_info "Creating Steam User and Application Directories"
useradd --system \
  --create-home \
  --home-dir /home/steam \
  --shell /usr/sbin/nologin \
  steam
mkdir -p /opt/valheim/server /opt/valheim/data /opt/steamcmd
chown -R steam:steam /opt/valheim /opt/steamcmd /home/steam
msg_ok "Created Steam User and Application Directories"

fetch_and_deploy_from_url \
  "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
  "/opt/steamcmd"
chown -R steam:steam /opt/steamcmd

msg_info "Installing Valheim Dedicated Server (Patience)"
# SteamCMD can fail with "Missing configuration" on its first app_update
# after a fresh install (appinfo cache not ready) — retry covers it.
for attempt in 1 2 3; do
  if $STD runuser -u steam -- /opt/steamcmd/steamcmd.sh \
    +force_install_dir /opt/valheim/server \
    +login anonymous \
    +app_update 896660 validate \
    +quit; then
    break
  fi
  if [[ $attempt -eq 3 ]]; then
    msg_error "SteamCMD failed to install Valheim after 3 attempts"
    exit 1
  fi
  sleep 5
done
msg_ok "Installed Valheim Dedicated Server"

msg_info "Writing Server Settings"
EXTRA_ARGS=""
if [[ "${var_crossplay,,}" =~ ^(y|yes)$ ]]; then
  EXTRA_ARGS="-crossplay"
fi
cat <<EOF >/opt/valheim/valheim.env
SERVER_NAME=${var_server_name}
WORLD_NAME=${var_world_name}
SERVER_PASS=${var_server_password}
EXTRA_ARGS=${EXTRA_ARGS}
EOF
chown steam:steam /opt/valheim/valheim.env
chmod 600 /opt/valheim/valheim.env
msg_ok "Wrote Server Settings"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/valheim.service
[Unit]
Description=Valheim Dedicated Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=steam
Group=steam
WorkingDirectory=/opt/valheim/server
EnvironmentFile=/opt/valheim/valheim.env
Environment=LANG=C.UTF-8
Environment=HOME=/home/steam
Environment=LD_LIBRARY_PATH=/opt/valheim/server/linux64
Environment=SteamAppId=892970
ExecStart=/opt/valheim/server/valheim_server.x86_64 -nographics -batchmode \\
  -name "\${SERVER_NAME}" -world "\${WORLD_NAME}" -password "\${SERVER_PASS}" \\
  -port 2456 -public 0 -savedir /opt/valheim/data \${EXTRA_ARGS}
Restart=on-failure
RestartSec=10
KillSignal=SIGINT
TimeoutStopSec=120
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now valheim
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
