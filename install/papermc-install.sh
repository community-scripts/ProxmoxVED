#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Dmytro (vorotech)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/PaperMC/Paper

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

JAVA_VERSION="21" setup_java

mkdir -p /opt/minecraft
if ! id -u minecraft >/dev/null 2>&1; then useradd -r -m -s /bin/bash minecraft; fi
chown -R minecraft:minecraft /opt/minecraft
cd /opt/minecraft

printf '%s\n' "eula=true" > eula.txt

# Autosize memory: Xms=RAM/4, Xmx=RAM/2; floors 1024M/2048M; cap Xmx ≤16G.
mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo); mem_mb=$((mem_kb/1024))
xmx=$(( mem_mb/2 ))
if (( xmx < 2048 )); then
  xmx=2048
fi
(( xmx > 16384 )) && xmx=16384
xms=$(( mem_mb/4 ))
if (( xms < 1024 )); then
  xms=1024
fi
(( xms > xmx )) && xms=$xmx

msg_info "Installing PaperMC"
PAPER_API_ROOT="https://api.papermc.io/v2/projects/paper"
LATEST_VERSION=$(curl -fsSL "${PAPER_API_ROOT}" | jq -r '.versions | last')
LATEST_BUILD=$(curl -fsSL "${PAPER_API_ROOT}/versions/${LATEST_VERSION}" | jq -r '.builds | last')
BUILD_JSON=$(curl -fsSL "${PAPER_API_ROOT}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}")
EXPECTED_SHA=$(printf '%s' "$BUILD_JSON" | jq -r '.downloads.application.sha256')
JAR_NAME=$(printf '%s' "$BUILD_JSON" | jq -r '.downloads.application.name')
DOWNLOAD_URL="${PAPER_API_ROOT}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}/downloads/${JAR_NAME}"

download_with_progress ${DOWNLOAD_URL} /opt/minecraft/server.jar

cd /opt/minecraft
ACTUAL_SHA=$(sha256sum server.jar | awk '{print $1}')
if [[ -n "$EXPECTED_SHA" && "$EXPECTED_SHA" != "null" ]]; then
  if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    msg_error "SHA256 mismatch for PaperMC (expected ${EXPECTED_SHA}, got ${ACTUAL_SHA})"
    exit 1
  fi
  msg_ok "SHA256 verified: ${ACTUAL_SHA}"
else
  msg_warn "No upstream SHA provided; computed: ${ACTUAL_SHA}"
fi

msg_info "Installing essential plugins"
mkdir /opt/minecraft/plugins
download_with_progress https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot /opt/minecraft/plugins/Geyser-Spigot.jar
msg_ok "Deployed: Geyser plugin"
download_with_progress https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot /opt/minecraft/plugins/floodgate-spigot.jar
msg_ok "Deployed: Floodgate plugin"
fetch_and_deploy_gh_release "MCDash.jar" "gnmyt/MCDash" "singlefile" "latest" "/opt/minecraft/plugins" "MCDash-*.jar"
msg_ok "Plugins installed"

cat <<EOF >start.sh
#!/usr/bin/env bash
exec java -Xms${xms}M -Xmx${xmx}M -jar server.jar nogui
EOF

chmod +x start.sh
chown -R minecraft:minecraft /opt/minecraft

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/minecraft.service
[Unit]
Description=PaperMC Minecraft Server
After=network.target

[Service]
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft
ExecStart=/opt/minecraft/start.sh
Restart=on-failure
UMask=0027

# NOTE: Systemd hardening options to reduce attack surface
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictNamespaces=true
CapabilityBoundingSet=
AmbientCapabilities=
ReadWritePaths=/opt/minecraft

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/mc-backup.service
[Unit]
Description=Minecraft backup (tar)

[Service]
Type=oneshot
ExecStart=/bin/mkdir -p "${BACKUP_DIR}"
ExecStart=/bin/bash -c 'tar -czf "${BACKUP_DIR}/java-$(date +%%F).tar.gz" "${MC_SRC_DIR}"'
ExecStartPost=/bin/bash -c 'find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +"${RETAIN_DAYS:-7}" -delete'

Environment="MC_SRC_DIR=/opt/minecraft"
Environment="BACKUP_DIR=/var/backups/minecraft"
Environment="RETAIN_DAYS=7"
EOF

cat <<EOF >/etc/systemd/system/mc-backup.timer
[Unit]
Description=Nightly Minecraft backup

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl enable -q --now minecraft
systemctl enable -q mc-backup.timer
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
