#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: SavageCore
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vogler/free-games-claimer
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"

setup_deb822_repo \
	"TurboVNC" \
	"https://packagecloud.io/dcommander/turbovnc/gpgkey" \
	"https://packagecloud.io/dcommander/turbovnc/any/" \
	"any" \
	"main"

setup_deb822_repo \
	"VirtualGL" \
	"https://packagecloud.io/dcommander/virtualgl/gpgkey" \
	"https://packagecloud.io/dcommander/virtualgl/any/" \
	"any" \
	"main"

install_packages_with_retry \
  "git" \
  "ratpoison" \
  "virtualgl" \
  "turbovnc" \
  "websockify" \
  "libnss3" \
  "libnspr4" \
  "libatk1.0-0" \
  "libatk-bridge2.0-0" \
  "libcups2" \
  "libxkbcommon0" \
  "libatspi2.0-0" \
  "libxcomposite1" \
  "libgbm1" \
  "libpango-1.0-0" \
  "libcairo2" \
  "libasound2" \
  "libxfixes3" \
  "libxdamage1"

msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PYTHON_VERSION="3.12" setup_uv

$STD uv python update-shell
$STD uv pip install apprise --system

msg_info "Installing free-games-claimer"
msg_info "Cloning Repository"
$STD git clone -b dev https://github.com/vogler/free-games-claimer.git /opt/free-games-claimer
cd /opt/free-games-claimer || exit
msg_ok "Cloned Repository"
msg_info "Installing NPM Packages"
$STD npm install
$STD npx patchright install chromium --no-shell
msg_ok "Installed NPM Packages"

# Install noVNC after patchright to avoid conflicts
msg_info "Install noVNC"
install_packages_with_retry "novnc"
msg_ok "Installed noVNC"
$STD ln -s /usr/share/novnc/vnc_auto.html /usr/share/novnc/index.html

mkdir -p /opt/free-games-claimer/data
cat <<'EOF' >/opt/free-games-claimer/data/config.env
# For more information on configuration options, please visit:
# https://github.com/vogler/free-games-claimer#configuration--options

# AliExpress
AE_EMAIL=
AE_PASSWORD=

# Epic Games
EG_EMAIL=
EG_PASSWORD=
EG_OTPKEY=

# GOG.com
GOG_EMAIL=
GOG_PASSWORD=

# Legacy Games
LG_EMAIL=

# Prime Gaming
PG_EMAIL=
PG_PASSWORD=
PG_OTPKEY=
PG_REDEEM=0
PG_CLAIMDLC=0

# Apprise notifications
NOTIFY=
EOF

msg_ok "Installed free-games-claimer"

msg_info "Creating VNC Service"
vnc_service_path="/etc/systemd/system/free-games-claimer-vnc.service"
cat <<'EOF' >"$vnc_service_path"
[Unit]
Description=free-games-claimer VNC Display Server
Before=free-games-claimer.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=HOME=/root
ExecStart=/opt/TurboVNC/bin/vncserver :1 -geometry 1920x1080 -depth 24 -rfbport 5900 -SecurityTypes None -xstartup /usr/bin/ratpoison
ExecStart=/usr/bin/websockify -D --web /usr/share/novnc/ 6080 localhost:5900
ExecStop=/opt/TurboVNC/bin/vncserver -kill :1
ExecStop=/usr/bin/pkill -f websockify

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now free-games-claimer-vnc.service
msg_ok "Created VNC Service"

msg_info "Creating Service"
service_path="/etc/systemd/system/free-games-claimer.service"
cat <<'EOF' >"$service_path"
[Unit]
Description=free-games-claimer
After=syslog.target network.target free-games-claimer-vnc.service
Requires=free-games-claimer-vnc.service

[Service]
Type=simple
Environment=DISPLAY=:1
Environment=SHOW=1
Environment=WIDTH=1920
Environment=HEIGHT=1080
ExecStart=/bin/bash -c 'node epic-games; node prime-gaming; node gog; node aliexpress'
KillMode=control-group
KillSignal=SIGTERM
TimeoutStopSec=10

SyslogIdentifier=free-games-claimer
StandardOutput=journal

WorkingDirectory=/opt/free-games-claimer
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q free-games-claimer.service
msg_ok "Created Service"

msg_info "Creating Cron Job"
crontab -l 2>/dev/null | grep -v "free-games-claimer" > /tmp/crontab.tmp || true
echo "30 18 * * * systemctl start free-games-claimer.service" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm -f /tmp/crontab.tmp
msg_ok "Created Cron Job (daily at 18:30)"

motd_ssh
customize
cleanup_lxc
