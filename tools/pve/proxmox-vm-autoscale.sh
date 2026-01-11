#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: fabriziosalmi
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fabriziosalmi/proxmox-vm-autoscale

# Security: Pinned to specific release for reproducibility and integrity
RELEASE_VERSION="v1.2.0"
RELEASE_COMMIT="faaefbb0c3e1584b7349994a2c35ef5069d222a0"
REPO_URL="https://github.com/fabriziosalmi/proxmox-vm-autoscale"
INSTALL_DIR="/opt/vm_autoscale"
SERVICE_NAME="vm_autoscale"

# Pinned Python dependencies with exact versions
REQUIREMENTS_CONTENT='paramiko==3.4.0
PyYAML==6.0.1
requests==2.31.0'

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

RD=$(echo "\033[01;31m")
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

set -euo pipefail
shopt -s inherit_errexit nullglob

msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
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

verify_commit() {
  local dir="$1"
  local expected_commit="$2"
  local actual_commit

  actual_commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "unknown")

  if [[ "$actual_commit" != "$expected_commit" ]]; then
    msg_error "Commit verification failed!"
    msg_error "Expected: ${expected_commit}"
    msg_error "Got: ${actual_commit}"
    exit 1
  fi
  msg_ok "Commit verification passed"
}

install_dependencies() {
  msg_info "Installing system dependencies"
  apt update -qq
  apt install -y -qq \
    python3 \
    python3-venv \
    python3-pip \
    git \
    curl \
    sudo &>/dev/null
  msg_ok "Installed system dependencies"
}

backup_config() {
  if [[ -f "${INSTALL_DIR}/config.yaml" ]]; then
    msg_info "Backing up existing configuration"
    cp "${INSTALL_DIR}/config.yaml" "/tmp/vm_autoscale_config.yaml.bak.$(date +%F_%H%M%S)"
    msg_ok "Configuration backed up"
  fi
}

restore_config() {
  local latest_backup
  latest_backup=$(ls -t /tmp/vm_autoscale_config.yaml.bak.* 2>/dev/null | head -1 || true)

  if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
    msg_info "Restoring previous configuration"
    cp "$latest_backup" "${INSTALL_DIR}/config.yaml"
    msg_ok "Configuration restored"
  fi
}

install_vm_autoscale() {
  header_info
  echo -e "\nThis script will install VM AutoScale ${RELEASE_VERSION}.\n"
  echo -e "${YW}Source:${CL} ${REPO_URL}"
  echo -e "${YW}Pinned Commit:${CL} ${RELEASE_COMMIT}\n"

  while true; do
    read -p "Start the VM AutoScale installation (y/n)? " yn
    case $yn in
      [Yy]*) break ;;
      [Nn]*) echo "Installation cancelled."; exit 0 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done

  check_root
  check_pve
  install_dependencies

  # Backup existing config if updating
  backup_config

  # Remove existing installation if present
  if [[ -d "$INSTALL_DIR" ]]; then
    msg_info "Removing existing installation"
    systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
    systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    msg_ok "Removed existing installation"
  fi

  # Clone repository at specific tag
  msg_info "Cloning VM AutoScale repository (${RELEASE_VERSION})"
  git clone --depth 1 --branch "${RELEASE_VERSION}" -q "$REPO_URL" "$INSTALL_DIR"
  msg_ok "Repository cloned to ${INSTALL_DIR}"

  # Verify the commit hash for security
  msg_info "Verifying repository integrity"
  verify_commit "$INSTALL_DIR" "$RELEASE_COMMIT"

  # Setup Python virtual environment
  msg_info "Setting up Python virtual environment"
  cd "$INSTALL_DIR"
  python3 -m venv venv
  source venv/bin/activate

  # Install Python dependencies with pinned versions
  msg_info "Installing Python dependencies (pinned versions)"
  pip install --quiet --upgrade pip

  # Create secure requirements file with pinned versions
  echo "${REQUIREMENTS_CONTENT}" > "${INSTALL_DIR}/requirements-pinned.txt"
  pip install --quiet -r "${INSTALL_DIR}/requirements-pinned.txt"

  deactivate
  msg_ok "Python environment configured"

  # Restore previous configuration if available
  restore_config

  # Create systemd service
  msg_info "Creating systemd service"
  cat <<EOF >/etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=VM AutoScale - Automatic VM resource scaling for Proxmox
After=network.target pve-cluster.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/venv/bin/python3 ${INSTALL_DIR}/autoscale.py
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now ${SERVICE_NAME}.service
  msg_ok "Systemd service created and enabled"

  # Save version info
  echo "${RELEASE_VERSION}" > "${INSTALL_DIR}/version.txt"
  echo "${RELEASE_COMMIT}" > "${INSTALL_DIR}/commit.txt"

  msg_ok "VM AutoScale ${RELEASE_VERSION} installed successfully!"

  echo ""
  echo -e "${GN}Installation Complete!${CL}"
  echo ""
  echo -e "${YW}Configuration:${CL}"
  echo -e "  Edit: ${GN}${INSTALL_DIR}/config.yaml${CL}"
  echo ""
  echo -e "${YW}Important Requirements for VMs:${CL}"
  echo -e "  For live scaling to work, ensure on each VM:"
  echo -e "  • ${GN}Enable NUMA:${CL} VM > Hardware > Processors > Enable NUMA ☑️"
  echo -e "  • ${GN}Enable CPU Hotplug:${CL} VM > Options > Hotplug > CPU ☑️"
  echo -e "  • ${GN}Enable Memory Hotplug:${CL} VM > Options > Hotplug > Memory ☑️"
  echo -e ""
  echo -e "  Note: ${YW}auto_configure_hotplug: true${CL} in config.yaml will auto-enable these"
  echo ""
  echo -e "${YW}Service Management:${CL}"
  echo -e "  Start:   ${GN}systemctl start ${SERVICE_NAME}${CL}"
  echo -e "  Stop:    ${GN}systemctl stop ${SERVICE_NAME}${CL}"
  echo -e "  Status:  ${GN}systemctl status ${SERVICE_NAME}${CL}"
  echo -e "  Logs:    ${GN}journalctl -u ${SERVICE_NAME} -f${CL}"
  echo ""
}

uninstall_vm_autoscale() {
  header_info
  echo -e "\nThis will uninstall VM AutoScale.\n"

  while true; do
    read -p "Are you sure you want to uninstall? (y/n) " yn
    case $yn in
      [Yy]*) break ;;
      [Nn]*) echo "Uninstall cancelled."; exit 0 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done

  check_root

  msg_info "Stopping service"
  systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
  systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
  msg_ok "Service stopped"

  msg_info "Removing service file"
  rm -f /etc/systemd/system/${SERVICE_NAME}.service
  systemctl daemon-reload
  msg_ok "Service file removed"

  msg_info "Removing installation directory"
  rm -rf "$INSTALL_DIR"
  msg_ok "Installation directory removed"

  msg_ok "VM AutoScale uninstalled successfully!"
}

update_vm_autoscale() {
  header_info
  echo -e "\nThis will update VM AutoScale to ${RELEASE_VERSION}.\n"

  if [[ ! -d "$INSTALL_DIR" ]]; then
    msg_error "VM AutoScale is not installed. Please install first."
    exit 1
  fi

  # Check current version
  local current_version
  current_version=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null || echo "unknown")

  if [[ "$current_version" == "$RELEASE_VERSION" ]]; then
    msg_ok "Already at version ${RELEASE_VERSION}"
    exit 0
  fi

  echo -e "${YW}Current version:${CL} ${current_version}"
  echo -e "${YW}New version:${CL} ${RELEASE_VERSION}"

  # Reinstall (backup/restore handled inside). install_vm_autoscale will handle confirmation.
  install_vm_autoscale
}

main() {
  header_info

  echo -e "\n${GN}VM AutoScale Installer${CL} - Version ${RELEASE_VERSION}\n"
  echo -e "Automatically scale VM resources on Proxmox hosts\n"
  echo -e "Select an option:\n"
  echo -e "  1) Install"
  echo -e "  2) Update"
  echo -e "  3) Uninstall"
  echo -e "  4) Exit"
  echo ""

  read -p "Enter choice [1-4]: " choice

  case $choice in
    1) install_vm_autoscale ;;
    2) update_vm_autoscale ;;
    3) uninstall_vm_autoscale ;;
    4) exit 0 ;;
    *) echo "Invalid option"; exit 1 ;;
  esac
}

main
