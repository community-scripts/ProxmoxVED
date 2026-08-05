#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: andrewtryder
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/andrewtryder/unifi-netwatcher

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  sqlite3 \
  tzdata
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.14" setup_uv

msg_info "Creating NetWatcher user and directories"
if ! getent group netwatcher >/dev/null; then
  groupadd --system netwatcher
fi
if ! id -u netwatcher >/dev/null 2>&1; then
  useradd --system --gid netwatcher --home-dir /var/lib/netwatcher \
    --shell /usr/sbin/nologin --create-home netwatcher
fi
install -d -m 0755 -o root -g root /opt/netwatcher
install -d -m 0755 -o root -g root /opt/netwatcher/releases
install -d -m 0750 -o root -g netwatcher /etc/netwatcher
install -d -m 0700 -o netwatcher -g netwatcher /var/lib/netwatcher
install -d -m 0700 -o netwatcher -g netwatcher /var/lib/netwatcher/backups
msg_ok "Created NetWatcher user and directories"

RELEASE_TAG="$(get_latest_github_release "andrewtryder/unifi-netwatcher")"
[[ -n "$RELEASE_TAG" ]] || {
  msg_error "Could not resolve latest NetWatcher release from GitHub"
  exit 1
}
RELEASE_VER="${RELEASE_TAG#v}"
RELEASE_DIR="/opt/netwatcher/releases/${RELEASE_VER}"

fetch_and_deploy_gh_release "netwatcher" "andrewtryder/unifi-netwatcher" "tarball" "$RELEASE_TAG" "$RELEASE_DIR"

msg_info "Validating release assets"
if [[ ! -f "${RELEASE_DIR}/app/web/static/app.css" ]]; then
  msg_error "Missing built static asset: app/web/static/app.css"
  exit 1
fi
if [[ ! -f "${RELEASE_DIR}/app/web/static/js/htmx.min.js" ]]; then
  msg_error "Missing built static asset: app/web/static/js/htmx.min.js"
  exit 1
fi
if [[ ! -d "${RELEASE_DIR}/app/web/static/fonts" ]]; then
  msg_error "Missing built static fonts directory"
  exit 1
fi
if [[ ! -f "${RELEASE_DIR}/uv.lock" ]] || [[ ! -f "${RELEASE_DIR}/alembic.ini" ]]; then
  msg_error "Release is missing uv.lock or alembic.ini"
  exit 1
fi
msg_ok "Validated release assets"

msg_info "Installing Python environment (uv sync --frozen)"
cd "$RELEASE_DIR" || exit 1
$STD uv sync --frozen --no-dev
chown -R root:root "$RELEASE_DIR"
chmod -R a+rX "$RELEASE_DIR"
# Keep the venv usable by the service user for execution (dirs need traverse)
find "$RELEASE_DIR" -type d -exec chmod 755 {} +
find "$RELEASE_DIR" -type f -exec chmod 644 {} +
chmod -R a+x "${RELEASE_DIR}/.venv/bin"
$STD "${RELEASE_DIR}/.venv/bin/python" -c "import uvicorn, alembic, app.main"
ln -sfn "$RELEASE_DIR" /opt/netwatcher/current
msg_ok "Installed Python environment"

msg_info "Writing configuration"
cat <<EOF >/etc/netwatcher/netwatcher.env
APP_ENV=production
APP_SECRET_KEY=
APP_SECRET_KEY_PATH=/var/lib/netwatcher/app-secret.key

DATABASE_URL=sqlite:////var/lib/netwatcher/netwatcher.db

UNIFI_URL=https://unifi.example.local
UNIFI_USERNAME=netwatcher
UNIFI_PASSWORD=change-me
UNIFI_SITE=default
UNIFI_VERIFY_SSL=true
UNIFI_TIMEOUT_SECONDS=10
UNIFI_MOCK_MODE=true
UNIFI_DRY_RUN_BLOCKS=true

SCAN_INTERVAL_SECONDS=300
ALERT_COOLDOWN_SECONDS=21600
OBSERVATION_RETENTION_DAYS=30
EVENT_RETENTION_DAYS=90

SECURITY_RECOVERY_BYPASS=false
EOF
chown root:netwatcher /etc/netwatcher/netwatcher.env
chmod 0640 /etc/netwatcher/netwatcher.env
msg_ok "Wrote configuration"

msg_info "Running database migrations"
set -a
# shellcheck source=/dev/null
source /etc/netwatcher/netwatcher.env
set +a
cd /opt/netwatcher/current || exit 1
runuser -u netwatcher --preserve-environment -- \
  /opt/netwatcher/current/.venv/bin/alembic upgrade head
# Ensure DB files are private to the service user
if [[ -f /var/lib/netwatcher/netwatcher.db ]]; then
  chown netwatcher:netwatcher /var/lib/netwatcher/netwatcher.db
  chmod 0600 /var/lib/netwatcher/netwatcher.db
fi
msg_ok "Ran database migrations"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/netwatcher.service
[Unit]
Description=NetWatcher for UniFi
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=netwatcher
Group=netwatcher
WorkingDirectory=/opt/netwatcher/current
EnvironmentFile=/etc/netwatcher/netwatcher.env
Environment=PATH=/opt/netwatcher/current/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
ExecStart=/opt/netwatcher/current/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8080 --workers 1
Restart=on-failure
RestartSec=5
TimeoutStartSec=120
TimeoutStopSec=30
UMask=0077

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
LockPersonality=true
CapabilityBoundingSet=
AmbientCapabilities=
ReadWritePaths=/var/lib/netwatcher
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
EOF
# MemoryDenyWriteExecute is intentionally omitted: Python C extensions
# (cryptography / argon2-cffi) require executable mappings.
systemctl enable -q --now netwatcher
msg_ok "Created Service"

msg_info "Waiting for /readyz"
READY=0
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/readyz >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
if [[ "$READY" -ne 1 ]]; then
  msg_error "NetWatcher did not become ready on http://127.0.0.1:8080/readyz"
  journalctl -u netwatcher -n 50 --no-pager || true
  exit 1
fi
# Key file is generated on first start when APP_SECRET_KEY is empty
if [[ -f /var/lib/netwatcher/app-secret.key ]]; then
  chown netwatcher:netwatcher /var/lib/netwatcher/app-secret.key
  chmod 0600 /var/lib/netwatcher/app-secret.key
fi
msg_ok "NetWatcher is ready"

motd_ssh
customize
cleanup_lxc
