#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nanja-at-web
# Co-Author: OpenAI Codex
# License: MIT
# Source: https://github.com/Nanja-at-web/namer

set -euo pipefail

if [[ -n "${FUNCTIONS_FILE_PATH:-}" ]]; then
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
else
  STD=""
  color() { :; }
  verb_ip6() { :; }
  catch_errors() { :; }
  setting_up_container() { :; }
  network_check() { :; }
  update_os() { :; }
  motd_ssh() { :; }
  customize() { :; }
  cleanup_lxc() { :; }
  msg_info() { printf '==> %s\n' "$1"; }
  msg_ok() { printf '==> %s\n' "$1"; }
fi

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP_USER="namer"
APP_GROUP="namer"
APP_HOME="/var/lib/namer"
APP_ETC="/etc/namer"
APP_OPT="/opt/namer"
APP_VENV="/opt/namer/venv"
APP_VERSION_FILE="/opt/namer_version.txt"
APP_CONFIG="/etc/namer/namer.cfg"
APP_ENV_FILE="/etc/default/namer"
APP_SERVICE="namer-watchdog.service"
APP_INSTALLER_COPY="/opt/namer/namer-install.sh"
NAS_MOUNT="/mnt/nas"
APP_WATCH="${APP_HOME}/watch"
APP_WORK="${APP_HOME}/work"
APP_FAILED="${APP_HOME}/failed"
APP_DEST="${APP_HOME}/dest"
APP_DATABASE="${APP_HOME}/database"
APP_PIP_SPEC="${NAMER_PIP_SPEC:-git+https://github.com/Nanja-at-web/namer.git@codex/proxmox-setup-wizard}"

log() {
  printf '[namer-install] %s\n' "$*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "Run this installer as root inside a Debian-based Proxmox LXC."
    exit 1
  fi
}

install_packages() {
  msg_info "Installing Dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    curl \
    ffmpeg \
    git \
    nfs-common \
    python3-pip \
    python3 \
    python3-venv
  msg_ok "Installed Dependencies"
}

create_layout() {
  getent group "${APP_GROUP}" >/dev/null 2>&1 || groupadd --system "${APP_GROUP}"

  if ! id -u "${APP_USER}" >/dev/null 2>&1; then
    useradd \
      --system \
      --gid "${APP_GROUP}" \
      --home "${APP_HOME}" \
      --create-home \
      --shell /usr/sbin/nologin \
      "${APP_USER}"
  fi

  install -d -o "${APP_USER}" -g "${APP_GROUP}" "${APP_HOME}"
  install -d -o root -g root "${APP_ETC}"
  install -d -o root -g root "${APP_OPT}"
  install -d -o "${APP_USER}" -g "${APP_GROUP}" "${APP_WATCH}"
  install -d -o "${APP_USER}" -g "${APP_GROUP}" "${APP_WORK}"
  install -d -o "${APP_USER}" -g "${APP_GROUP}" "${APP_FAILED}"
  install -d -o "${APP_USER}" -g "${APP_GROUP}" "${APP_DEST}"
  install -d -o "${APP_USER}" -g "${APP_GROUP}" "${APP_DATABASE}"
  install -d -o root -g root "${NAS_MOUNT}"
}

install_namer() {
  msg_info "Installing Namer"
  python3 -m venv "${APP_VENV}"
  "${APP_VENV}/bin/pip" install --upgrade pip
  if [[ "${APP_PIP_SPEC}" == "namer" ]]; then
    python3 -m pip install --upgrade "${APP_PIP_SPEC}"
    "${APP_VENV}/bin/pip" install --upgrade "${APP_PIP_SPEC}"
  else
    "${APP_VENV}/bin/pip" install --upgrade "${APP_PIP_SPEC}"
  fi
  "${APP_VENV}/bin/python" - <<'PY' >"${APP_VERSION_FILE}"
import importlib.metadata

print(importlib.metadata.version("namer"))
PY
  msg_ok "Installed Namer"
}

write_default_config() {
  if [[ -f "${APP_CONFIG}" ]]; then
    log "Config already exists at ${APP_CONFIG}; leaving it in place."
    return
  fi

  "${APP_VENV}/bin/python" - <<'PY'
from configupdater import ConfigUpdater
from importlib import resources
from pathlib import Path

config_path = Path("/etc/namer/namer.cfg")
config_text = resources.files("namer").joinpath("namer.cfg.default").read_text(encoding="utf-8")
updater = ConfigUpdater(allow_no_value=True)
updater.read_string(config_text)

updater["namer"]["porndb_token"].value = ""
updater["namer"]["database_path"].value = "/var/lib/namer/database"

updater["setup"]["is_setup_complete"].value = "False"
updater["setup"]["setup_mode"].value = "wizard"
updater["setup"]["storage_mode"].value = "nfs"
updater["setup"]["nas_host"].value = ""
updater["setup"]["nas_share"].value = ""
updater["setup"]["nas_mount_path"].value = "/mnt/nas"
updater["setup"]["nas_mount_options"].value = "defaults,_netdev"

updater["watchdog"]["watch_dir"].value = "/var/lib/namer/watch"
updater["watchdog"]["work_dir"].value = "/var/lib/namer/work"
updater["watchdog"]["failed_dir"].value = "/var/lib/namer/failed"
updater["watchdog"]["dest_dir"].value = "/var/lib/namer/dest"
updater["watchdog"]["web"].value = "True"

config_path.write_text(str(updater), encoding="utf-8")
PY

  chown "${APP_USER}:${APP_GROUP}" "${APP_CONFIG}"
  chmod 0640 "${APP_CONFIG}"
  msg_ok "Created bootstrap config"
}

write_environment_file() {
  cat >"${APP_ENV_FILE}" <<EOF
NAMER_CONFIG=${APP_CONFIG}
EOF
}

persist_installer_copy() {
  if [[ -f "${BASH_SOURCE[0]}" ]]; then
    install -D -m 0755 "${BASH_SOURCE[0]}" "${APP_INSTALLER_COPY}"
  fi
}

write_service() {
  msg_info "Creating Service"
  cat >"/etc/systemd/system/${APP_SERVICE}" <<EOF
[Unit]
Description=Namer watchdog
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
EnvironmentFile=${APP_ENV_FILE}
ExecStart=${APP_VENV}/bin/python -m namer watchdog
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  msg_ok "Created Service"
}

print_next_steps() {
  cat <<EOF

Namer installation completed.

Package source:
  ${APP_PIP_SPEC}

Next steps:
  1. Start the service: systemctl enable --now ${APP_SERVICE}
  2. Open the web UI on port 6980 inside your LXC network.
  3. Finish the setup wizard with:
     - TPDB API token
     - NFS host/share
     - watch/work/failed/dest paths
  4. The service starts with local bootstrap directories so the wizard is reachable immediately.
  5. Persist the NAS mount and switch watch/dest paths after validating your final NFS settings.

EOF
}

main() {
  require_root
  install_packages
  create_layout
  install_namer
  write_default_config
  write_environment_file
  write_service
  persist_installer_copy
  systemctl daemon-reload
  motd_ssh
  customize
  cleanup_lxc
  print_next_steps
}

main "$@"
