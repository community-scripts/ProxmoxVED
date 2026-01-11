#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: fabriziosalmi
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fabriziosalmi/proxmox-lxc-autoscale

# Source standard functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)

# Configuration
RELEASE_VERSION="v1.0.0"
REPO="fabriziosalmi/proxmox-lxc-autoscale"
INSTALL_DIR="/opt/lxc_autoscale"
SERVICE_NAME="lxc_autoscale"

# Pinned Python dependencies
REQUIREMENTS_CONTENT='paramiko==3.4.0
PyYAML==6.0.1
requests==2.31.0'

header_info() {
  clear
  cat <<"EOF"
    __   _  ________   ___         __       _____            __
   / /  | |/_/ ____/  /   | __  __/ /____  / ___/_________ _/ /__
  / /  _>  </ /      / /| |/ / / / __/ _ \ \__ \/ ___/ __ `/ / _ \
 / /__/ /|  / /___  / ___ / /_/ / /_/  __/___/ / /__/ /_/ / /  __/
/_____/_/ |_\____/ /_/  |_\__,_/\__/\___//____/\___/\__,_/_/\___/

EOF
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root"
    exit 1
  fi
}

check_pve() {
  if ! command -v pveversion &>/dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
    exit 1
  fi
}

setup_python_env() {
  msg_info "Setting up Python virtual environment"
  cd "$INSTALL_DIR"
  python3 -m venv venv
  source venv/bin/activate

  msg_info "Installing Python dependencies"
  pip install --quiet --upgrade pip
  echo "${REQUIREMENTS_CONTENT}" > "${INSTALL_DIR}/requirements-pinned.txt"
  pip install --quiet -r "${INSTALL_DIR}/requirements-pinned.txt"

  deactivate
  msg_ok "Python environment configured"
}

create_service() {
  msg_info "Creating systemd service"
  cat <<EOF >/etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=LXC AutoScale - Automatic LXC container resource scaling
After=network.target pve-cluster.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/lxc_autoscale
ExecStart=${INSTALL_DIR}/venv/bin/python3 ${INSTALL_DIR}/lxc_autoscale/lxc_autoscale.py
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now ${SERVICE_NAME}.service
  msg_ok "Service created and enabled"
}

backup_config() {
  if [[ -f "${INSTALL_DIR}/lxc_autoscale/lxc_autoscale.yaml" ]]; then
    msg_info "Backing up configuration"
    cp "${INSTALL_DIR}/lxc_autoscale/lxc_autoscale.yaml" "/tmp/lxc_autoscale.yaml.bak.$(date +%F_%H%M%S)"
    msg_ok "Configuration backed up"
  fi
}

restore_config() {
  local latest_backup
  latest_backup=$(ls -t /tmp/lxc_autoscale.yaml.bak.* 2>/dev/null | head -1 || true)

  if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
    msg_info "Restoring configuration"
    cp "$latest_backup" "${INSTALL_DIR}/lxc_autoscale/lxc_autoscale.yaml"
    msg_ok "Configuration restored"
  fi
}

install_lxc_autoscale() {
  header_info
  echo -e "\nInstalling LXC AutoScale ${RELEASE_VERSION}\n"

  while true; do
    read -p "Start installation (y/n)? " yn
    case $yn in
      [Yy]*) break ;;
      [Nn]*) echo "Cancelled."; exit 0 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done

  check_root
  check_pve

  msg_info "Installing dependencies"
  ensure_dependencies python3 python3-venv python3-pip curl sudo
  msg_ok "Dependencies installed"

  backup_config

  # Stop and remove existing installation
  if [[ -d "$INSTALL_DIR" ]]; then
    systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
    systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
  fi

  # Download and deploy using standard function
  msg_info "Downloading release ${RELEASE_VERSION}"
  fetch_and_deploy_gh_release "lxc_autoscale" "$REPO" "tarball" "$RELEASE_VERSION" "$INSTALL_DIR"
  msg_ok "Release deployed"

  setup_python_env
  restore_config
  create_service

  msg_ok "LXC AutoScale ${RELEASE_VERSION} installed successfully!"
  echo ""
  echo -e "Configuration: ${INSTALL_DIR}/lxc_autoscale/lxc_autoscale.yaml"
  echo -e "Service: systemctl status ${SERVICE_NAME}"
}

uninstall_lxc_autoscale() {
  header_info
  echo -e "\nUninstalling LXC AutoScale\n"

  while true; do
    read -p "Are you sure (y/n)? " yn
    case $yn in
      [Yy]*) break ;;
      [Nn]*) echo "Cancelled."; exit 0 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done

  check_root

  msg_info "Stopping service"
  systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
  systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
  msg_ok "Service stopped"

  msg_info "Removing files"
  rm -f /etc/systemd/system/${SERVICE_NAME}.service
  systemctl daemon-reload
  rm -rf "$INSTALL_DIR"
  msg_ok "Uninstalled"
}

update_lxc_autoscale() {
  header_info
  echo -e "\nUpdating to ${RELEASE_VERSION}\n"

  if [[ ! -d "$INSTALL_DIR" ]]; then
    msg_error "Not installed. Use install option."
    exit 1
  fi

  local current_version
  current_version=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null || echo "unknown")

  if [[ "$current_version" == "$RELEASE_VERSION" ]]; then
    msg_ok "Already at version ${RELEASE_VERSION}"
    exit 0
  fi

  echo -e "Current: ${current_version} → New: ${RELEASE_VERSION}"
  install_lxc_autoscale
}

main() {
  header_info

  echo -e "\nLXC AutoScale Installer - ${RELEASE_VERSION}\n"
  echo -e "Select an option:\n"
  echo -e "  1) Install"
  echo -e "  2) Update"
  echo -e "  3) Uninstall"
  echo -e "  4) Exit"
  echo ""

  read -p "Enter choice [1-4]: " choice

  case $choice in
    1) install_lxc_autoscale ;;
    2) update_lxc_autoscale ;;
    3) uninstall_lxc_autoscale ;;
    4) exit 0 ;;
    *) echo "Invalid option"; exit 1 ;;
  esac
}

main
