#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: fabriziosalmi
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fabriziosalmi/proxmox-vm-autoscale

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)

APP="VM AutoScale"
RELEASE_VERSION="v1.2.0"
REPO="fabriziosalmi/proxmox-vm-autoscale"
INSTALL_DIR="/opt/vm_autoscale"
SERVICE_NAME="vm_autoscale"
CONFIG_FILE="${INSTALL_DIR}/config.yaml"

header_info() {
  clear
  cat <<"EOF"
  _    ____  ___   ___         __       _____            __
 | |  / /  |/  /  /   | __  __/ /____  / ___/_________ _/ /__
 | | / / /|_/ /  / /| |/ / / / __/ _ \ \__ \/ ___/ __ `/ / _ \
 | |/ / /  / /  / ___ / /_/ / /_/  __/___/ / /__/ /_/ / /  __/
 |___/_/  /_/  /_/  |_\__,_/\__/\___//____/\___/\__,_/_/\___/

EOF
}

install_vm_autoscale() {
  header_info
  echo -e "\nInstalling ${APP} ${RELEASE_VERSION}\n"

  read -p "Start installation (y/n)? " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Cancelled."; exit 0; }

  [[ $EUID -ne 0 ]] && { msg_error "Run as root"; exit 1; }
  command -v pveversion &>/dev/null || { msg_error "Proxmox VE required"; exit 1; }

  # Backup existing config
  [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "/tmp/vm_autoscale_config.yaml.bak.$(date +%F_%H%M%S)"

  # Stop existing service
  if [[ -d "$INSTALL_DIR" ]]; then
    msg_info "Stopping existing service"
    systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
    systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    msg_ok "Stopped existing service"
  fi

  msg_info "Installing dependencies"
  ensure_dependencies curl sudo
  msg_ok "Installed dependencies"

  msg_info "Downloading ${APP} ${RELEASE_VERSION}"
  fetch_and_deploy_gh_release "vm_autoscale" "$REPO" "tarball" "$RELEASE_VERSION" "$INSTALL_DIR"
  msg_ok "Downloaded ${APP}"

  msg_info "Setting up Python environment"
  UV_VERSION="0.7.19" PYTHON_VERSION="3.12" setup_uv
  cd "$INSTALL_DIR"
  $STD uv venv
  $STD uv pip install paramiko==3.4.0 PyYAML==6.0.1 requests==2.31.0
  msg_ok "Setup Python environment"

  # Restore config if backup exists
  local latest_backup=$(ls -t /tmp/vm_autoscale_config.yaml.bak.* 2>/dev/null | head -1 || true)
  [[ -n "$latest_backup" && -f "$latest_backup" ]] && cp "$latest_backup" "$CONFIG_FILE"

  msg_info "Creating service"
  cat <<EOF >/etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=VM AutoScale - Automatic VM resource scaling for Proxmox
After=network.target pve-cluster.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/local/bin/uv run python3 ${INSTALL_DIR}/autoscale.py
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ${SERVICE_NAME}.service
  msg_ok "Created service"

  msg_ok "${APP} ${RELEASE_VERSION} installed"
  echo -e "\nConfiguration: ${CONFIG_FILE}"
  echo -e "Service: systemctl status ${SERVICE_NAME}"
}

update_vm_autoscale() {
  header_info
  echo -e "\nUpdating ${APP} to ${RELEASE_VERSION}\n"

  [[ ! -d "$INSTALL_DIR" ]] && { msg_error "Not installed"; exit 1; }

  local current_version=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null || echo "unknown")
  [[ "$current_version" == "$RELEASE_VERSION" ]] && { msg_ok "Already at ${RELEASE_VERSION}"; exit 0; }

  echo -e "Current: ${current_version} -> New: ${RELEASE_VERSION}\n"

  # Backup config
  [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "/tmp/vm_autoscale_config.yaml.bak.$(date +%F_%H%M%S)"

  msg_info "Stopping service"
  systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
  msg_ok "Stopped service"

  msg_info "Downloading ${APP} ${RELEASE_VERSION}"
  rm -rf "$INSTALL_DIR"
  fetch_and_deploy_gh_release "vm_autoscale" "$REPO" "tarball" "$RELEASE_VERSION" "$INSTALL_DIR"
  msg_ok "Downloaded ${APP}"

  msg_info "Setting up Python environment"
  cd "$INSTALL_DIR"
  $STD uv venv
  $STD uv pip install paramiko==3.4.0 PyYAML==6.0.1 requests==2.31.0
  msg_ok "Setup Python environment"

  # Restore config
  local latest_backup=$(ls -t /tmp/vm_autoscale_config.yaml.bak.* 2>/dev/null | head -1 || true)
  [[ -n "$latest_backup" && -f "$latest_backup" ]] && cp "$latest_backup" "$CONFIG_FILE"

  msg_info "Starting service"
  systemctl start ${SERVICE_NAME}.service
  msg_ok "Started service"

  msg_ok "${APP} updated to ${RELEASE_VERSION}"
}

uninstall_vm_autoscale() {
  header_info
  echo -e "\nUninstalling ${APP}\n"

  read -p "Are you sure (y/n)? " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Cancelled."; exit 0; }

  [[ $EUID -ne 0 ]] && { msg_error "Run as root"; exit 1; }

  msg_info "Stopping service"
  systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
  systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
  msg_ok "Stopped service"

  msg_info "Removing files"
  rm -f /etc/systemd/system/${SERVICE_NAME}.service
  systemctl daemon-reload
  rm -rf "$INSTALL_DIR"
  msg_ok "Removed files"

  msg_ok "${APP} uninstalled"
}

header_info
echo -e "\n${APP} Installer - ${RELEASE_VERSION}\n"
echo -e "  1) Install"
echo -e "  2) Update"
echo -e "  3) Uninstall"
echo -e "  4) Exit\n"

read -p "Enter choice [1-4]: " choice
case $choice in
  1) install_vm_autoscale ;;
  2) update_vm_autoscale ;;
  3) uninstall_vm_autoscale ;;
  4) exit 0 ;;
  *) echo "Invalid option"; exit 1 ;;
esac
