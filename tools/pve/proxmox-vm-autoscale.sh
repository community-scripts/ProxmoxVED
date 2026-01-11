#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: fabriziosalmi
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fabriziosalmi/proxmox-vm-autoscale

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
load_functions

function header_info {
  clear
  cat <<"EOF"
  _    ____  ___   ___         __       _____            __
 | |  / /  |/  /  /   | __  __/ /____  / ___/_________ _/ /__
 | | / / /|_/ /  / /| |/ / / / __/ _ \ \__ \/ ___/ __ `/ / _ \
 | |/ / /  / /  / ___ / /_/ / /_/  __/___/ / /__/ /_/ / /  __/
 |___/_/  /_/  /_/  |_\__,_/\__/\___//____/\___/\__,_/_/\___/

EOF
}

APP="VM AutoScale"
REPO="fabriziosalmi/proxmox-vm-autoscale"

header_info
echo -e "\n Loading..."

if ! command -v pveversion &>/dev/null; then
  msg_error "This script must be run on a Proxmox VE host"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  msg_error "This script must be run as root"
  exit 1
fi

INSTALL_DIR="/opt/vm_autoscale"
CONFIG_FILE="${INSTALL_DIR}/config.yaml"

install() {
  header_info
  echo -e "\nThis will install ${APP}.\n"

  while true; do
    read -p "Start the installation? (y/n): " yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*) exit 0 ;;
    *) echo "Please answer yes or no." ;;
    esac
  done

  if [[ -d "$INSTALL_DIR" ]]; then
    msg_info "Stopping existing service"
    systemctl stop vm_autoscale.service 2>/dev/null || true
    systemctl disable vm_autoscale.service 2>/dev/null || true
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "/tmp/vm_autoscale_config.yaml.bak"
    rm -rf "$INSTALL_DIR"
    msg_ok "Stopped existing service"
  fi

  fetch_and_deploy_gh_release "vm_autoscale" "$REPO" "tarball" "latest" "$INSTALL_DIR"

  msg_info "Setting up Python environment"
  setup_uv
  msg_ok "Set up Python environment"

  msg_info "Creating service"
  cat <<EOF >/etc/systemd/system/vm_autoscale.service
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
  systemctl daemon-reload
  systemctl enable -q --now vm_autoscale.service
  msg_ok "Created service"

  [[ -f "/tmp/vm_autoscale_config.yaml.bak" ]] && cp "/tmp/vm_autoscale_config.yaml.bak" "$CONFIG_FILE"

  msg_ok "${APP} installed successfully"
  echo -e "\nConfiguration: ${CONFIG_FILE}"
  echo -e "Service: systemctl status vm_autoscale"
}

update() {
  header_info
  echo -e "\nThis will update ${APP}.\n"

  if [[ ! -d "$INSTALL_DIR" ]]; then
    msg_error "No ${APP} installation found"
    exit 1
  fi

  msg_info "Stopping service"
  systemctl stop vm_autoscale.service 2>/dev/null || true
  msg_ok "Stopped service"

  [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "/tmp/vm_autoscale_config.yaml.bak"
  rm -rf "$INSTALL_DIR"

  fetch_and_deploy_gh_release "vm_autoscale" "$REPO" "tarball" "latest" "$INSTALL_DIR"

  [[ -f "/tmp/vm_autoscale_config.yaml.bak" ]] && cp "/tmp/vm_autoscale_config.yaml.bak" "$CONFIG_FILE"

  msg_info "Starting service"
  systemctl start vm_autoscale.service
  msg_ok "Started service"

  msg_ok "${APP} updated successfully"
}

uninstall() {
  header_info
  echo -e "\nThis will uninstall ${APP}.\n"

  if [[ ! -d "$INSTALL_DIR" ]]; then
    msg_error "No ${APP} installation found"
    exit 1
  fi

  while true; do
    read -p "Are you sure you want to uninstall? (y/n): " yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*) exit 0 ;;
    *) echo "Please answer yes or no." ;;
    esac
  done

  msg_info "Stopping service"
  systemctl stop vm_autoscale.service 2>/dev/null || true
  systemctl disable vm_autoscale.service 2>/dev/null || true
  msg_ok "Stopped service"

  msg_info "Removing files"
  rm -f /etc/systemd/system/vm_autoscale.service
  systemctl daemon-reload
  rm -rf "$INSTALL_DIR"
  msg_ok "Removed files"

  msg_ok "${APP} uninstalled successfully"
}

header_info
echo -e "\n${APP}\n"
OPTIONS=(
  "Install" "Install ${APP} on Proxmox VE"
  "Update" "Update ${APP} to latest version"
  "Uninstall" "Remove ${APP} from Proxmox VE"
)

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" \
  --menu "Select an option:" 12 50 3 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

case $CHOICE in
"Install") install ;;
"Update") update ;;
"Uninstall") uninstall ;;
*) exit 0 ;;
esac
