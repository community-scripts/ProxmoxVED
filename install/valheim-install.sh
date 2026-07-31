#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: PawelSzymanski89
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/PawelSzymanski89/valheim-proxmox

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD dpkg --add-architecture i386
$STD apt update
# libpulse-mainloop-glib0 is not optional: PlayFab Party (crossplay) fails to initialise
# without it, the server loops on "begin PlayFab create and join network" and hands out an
# empty join code.
$STD apt install -y \
  lib32gcc-s1 \
  libsdl2-2.0-0:i386 \
  libatomic1 \
  libpulse0 \
  libpulse-mainloop-glib0
msg_ok "Installed Dependencies"

setup_uv

msg_info "Creating valheim User"
$STD useradd -m -d /opt/valheim -s /bin/bash valheim
mkdir -p /opt/valheim/{steamcmd,server,data/worlds_local,backups,panel}
chown -R valheim:valheim /opt/valheim
msg_ok "Created valheim User"

msg_info "Setting up SteamCMD"
$STD runuser -u valheim -- env HOME=/opt/valheim bash -c \
  "cd /opt/valheim/steamcmd && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar zxf -"
# The first steamcmd run updates steamcmd itself and re-executes, dropping the rest of the
# command line - the app_update then dies with "Missing configuration". So: warm it up first.
$STD runuser -u valheim -- env HOME=/opt/valheim /opt/valheim/steamcmd/steamcmd.sh +login anonymous +quit || true
msg_ok "Set up SteamCMD"

msg_info "Downloading Valheim Server (~1.5 GB, this takes a while)"
$STD runuser -u valheim -- env HOME=/opt/valheim /opt/valheim/steamcmd/steamcmd.sh \
  +force_install_dir /opt/valheim/server +login anonymous +app_update 896660 validate +quit
[[ -x /opt/valheim/server/valheim_server.x86_64 ]] || {
  msg_error "Steam download failed"
  exit 1
}
msg_ok "Downloaded Valheim Server"

msg_info "Configuring Server"
# Launch settings live here so the panel has something to edit; start.sh only assembles args.
cat <<'EOF' >/opt/valheim/server.env
NAME='Valheim'
WORLD='Dedicated'
PASSWORD='valheim123'
PORT='2456'
PUBLIC='0'
CROSSPLAY='0'
PRESET=''
MODIFIERS=''
SETKEYS=''
EOF

cat <<'EOF' >/opt/valheim/start.sh
#!/bin/bash
export LD_LIBRARY_PATH="/opt/valheim/server/linux64:$LD_LIBRARY_PATH"
export SteamAppId=892970
NAME=Valheim; WORLD=Dedicated; PASSWORD=; PORT=2456; PUBLIC=0; CROSSPLAY=0; PRESET=; MODIFIERS=; SETKEYS=
[ -r /opt/valheim/server.env ] && . /opt/valheim/server.env
cd /opt/valheim/server

# BepInEx (installed by the panel on the first mod) is loaded by doorstop. These are the
# Doorstop 4 names from the pack's own start_server_bepinex.sh; the older DOORSTOP_ENABLE
# spelling is silently ignored and looks exactly like "mods do nothing".
if [ -d /opt/valheim/server/BepInEx ]; then
  export DOORSTOP_ENABLED=1
  export DOORSTOP_TARGET_ASSEMBLY=./BepInEx/core/BepInEx.Preloader.dll
  export LD_LIBRARY_PATH="./doorstop_libs:$LD_LIBRARY_PATH"
  export LD_PRELOAD="libdoorstop_x64.so:$LD_PRELOAD"
fi

ARGS=(-nographics -batchmode -name "$NAME" -port "$PORT" -world "$WORLD" -savedir /opt/valheim/data -public "$PUBLIC")
[ -n "$PASSWORD" ] && ARGS+=(-password "$PASSWORD")
[ "$CROSSPLAY" = "1" ] && ARGS+=(-crossplay)
[ -n "$PRESET" ] && ARGS+=(-preset "$PRESET")
for m in $MODIFIERS; do ARGS+=(-modifier "${m%%:*}" "${m#*:}"); done
for k in $SETKEYS; do ARGS+=(-setkey "$k"); done

exec ./valheim_server.x86_64 "${ARGS[@]}"
EOF

cat <<'EOF' >/opt/valheim/backup.sh
#!/bin/bash
SRC=/opt/valheim/data/worlds_local; DST=/opt/valheim/backups
[ -d "$SRC" ] || exit 0
ts=$(date +%Y%m%d-%H%M%S)
tar czf "$DST/world-$ts.tar.gz" -C "$SRC" . 2>/dev/null && echo "backup world-$ts.tar.gz"
ls -1t "$DST"/world-*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm -f
EOF

cat <<'EOF' >/opt/valheim/panel-passwd.sh
#!/bin/bash
# Reset the panel login without the panel: /opt/valheim/panel-passwd.sh [user] <password>
set -eu
ENV=/opt/valheim/panel.env
[ $# -ge 1 ] || { echo "usage: $0 [user] <password>"; exit 1; }
if [ $# -ge 2 ]; then USER_=$1; PASS=$2; else USER_=$(grep -oP "PANEL_USER='\K[^']*" $ENV || echo admin); PASS=$1; fi
[ ${#PASS} -ge 8 ] || { echo "password must be at least 8 characters"; exit 1; }
PORT=$(grep -oP "PANEL_PORT='\K[^']*" $ENV 2>/dev/null || echo 2460)
printf "PANEL_USER='%s'\nPANEL_PASS='%s'\nPANEL_PORT='%s'\n" "$USER_" "$PASS" "$PORT" >$ENV
chmod 600 $ENV
echo "panel login is now $USER_ / $PASS (no restart needed)"
EOF

for f in adminlist bannedlist permittedlist; do
  echo "// one player id per line" >/opt/valheim/data/${f}.txt
done
chmod +x /opt/valheim/{start.sh,backup.sh,panel-passwd.sh}
chown -R valheim:valheim /opt/valheim
msg_ok "Configured Server"

msg_info "Setting up Admin Panel"
fetch_and_deploy_gh_release "valheim-panel" "PawelSzymanski89/valheim-proxmox" "prebuild" "latest" "/opt/valheim/panel" "panel.tar.gz"
$STD uv venv /opt/valheim/panel/.venv
$STD /opt/valheim/panel/.venv/bin/python -m ensurepip
$STD /opt/valheim/panel/.venv/bin/pip install fastapi "uvicorn[standard]" pyyaml
# The starting password is the same on every install on purpose - the panel shows a red
# banner until it is changed and refuses to have the default set back.
cat <<'EOF' >/opt/valheim/panel.env
PANEL_USER='admin'
PANEL_PASS='valheim123'
PANEL_PORT='2460'
EOF
chmod 600 /opt/valheim/panel.env
msg_ok "Set up Admin Panel"

msg_info "Creating Services"
cat <<'EOF' >/etc/systemd/system/valheim.service
[Unit]
Description=Valheim dedicated server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=valheim
ExecStart=/opt/valheim/start.sh
Restart=on-failure
RestartSec=8
# SIGINT is what makes the server save the world before dying; SIGTERM loses it
KillSignal=SIGINT
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/valheim-panel.service
[Unit]
Description=Valheim admin panel
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/opt/valheim/panel.env
WorkingDirectory=/opt/valheim/panel
ExecStart=/bin/sh -c '/opt/valheim/panel/.venv/bin/uvicorn app:app --host 0.0.0.0 --port ${PANEL_PORT}'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/valheim-backup.service
[Unit]
Description=Valheim world backup

[Service]
Type=oneshot
User=valheim
ExecStart=/opt/valheim/backup.sh
EOF

cat <<'EOF' >/etc/systemd/system/valheim-backup.timer
[Unit]
Description=Valheim world backup every 2h

[Timer]
OnBootSec=10min
OnUnitActiveSec=2h

[Install]
WantedBy=timers.target
EOF

systemctl enable -q --now valheim valheim-panel valheim-backup.timer
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
