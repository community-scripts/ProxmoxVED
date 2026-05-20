#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021 (Slaviša Arežina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/mostafa-wahied/portracker
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)

set -Eeuo pipefail
trap 'error_handler' ERR

APP="portracker"
APP_TYPE="addon"
INSTALL_PATH="/opt/portracker"
BINARY_PATH="/usr/bin/npm start"
CONFIG_PATH="/opt/portracker/portracker.env"
DEFAULT_PORT=4999

load_functions

function header_info {
  clear
  cat <<"EOF"
                      __                  __
    ____  ____  _____/ /__________ ______/ /_____  _____
   / __ \/ __ \/ ___/ __/ ___/ __ `/ ___/ //_/ _ \/ ___/
  / /_/ / /_/ / /  / /_/ /  / /_/ / /__/ ,< /  __/ /
 / .___/\____/_/   \__/_/   \__,_/\___/_/|_|\___/_/
/_/
EOF
}

function get_ip() {
  local iface ip
  iface=$(ip -4 route | awk '/default/ {print $5; exit}')
  ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
  [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$ip" ]] && ip="127.0.0.1"
  echo "$ip"
}

function detect_os() {
  if [[ -f "/etc/alpine-release" ]]; then
    OS="Alpine"
    SERVICE_PATH="/etc/init.d/${APP,,}"
    PKG_INSTALL="apk add --no-cache"
  elif [[ -f "/etc/debian_version" ]]; then
    OS="Debian"
    SERVICE_PATH="/etc/systemd/system/${APP,,}.service"
    PKG_INSTALL="apt-get install -y"
  else
    msg_error "Unsupported OS. Exiting."
    exit 1
  fi
}

function stop_service() {
  if [[ "$OS" == "Debian" ]]; then
    systemctl stop "${APP,,}" &>/dev/null || true
  else
    rc-service "${APP,,}" stop &>/dev/null || true
  fi
}

function start_service() {
  if [[ "$OS" == "Debian" ]]; then
    systemctl start "${APP,,}" &>/dev/null
  else
    rc-service "${APP,,}" start &>/dev/null
  fi
}

function enable_service() {
  if [[ "$OS" == "Debian" ]]; then
    systemctl enable --now "${APP,,}" &>/dev/null
  else
    rc-update add "${APP,,}" default &>/dev/null
    rc-service "${APP,,}" start &>/dev/null
  fi
}

function disable_service() {
  if [[ "$OS" == "Debian" ]]; then
    systemctl disable --now "${APP,,}" &>/dev/null || true
  else
    rc-service "${APP,,}" stop &>/dev/null || true
    rc-update del "${APP,,}" &>/dev/null || true
  fi
}

function uninstall() {
  msg_info "Uninstalling ${APP}"
  disable_service
  rm -f "$SERVICE_PATH"
  rm -rf "$INSTALL_PATH"
  rm -f "$CONFIG_PATH"
  rm -f "/usr/local/bin/update_${APP,,}"
  msg_ok "${APP} has been uninstalled"
}

function update() {
  msg_info "Checking for updates"
  if check_for_gh_release "${APP,,}" "mostafa-wahied/portracker"; then
    msg_ok "Update available"
    stop_service
    mv "$INSTALL_PATH/portracker.env" /opt/portracker.env.backup
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "${APP,,}" "mostafa-wahied/portracker" "tarball"
    cd "$INSTALL_PATH/frontend"
    $STD npm ci --include=dev
    $STD npm run build

    cd "$INSTALL_PATH/backend"
    $STD npm ci --omit=dev
    mv "$INSTALL_PATH/frontend/dist" "$INSTALL_PATH/backend/public"
    mv /opt/portracker.env.backup "$INSTALL_PATH/portracker.env"
    start_service
    msg_ok "Updated ${APP} successfully"
  else
    msg_ok "${APP} is up-to-date"
  fi
  msg_ok "${APP} is up-to-date"
}

function install() {
  local port="${1:-$DEFAULT_PORT}"
  local ip
  ip=$(get_ip)

  msg_info "Installing dependencies"
  $PKG_INSTALL curl wget jq build-essential &>/dev/null
  $PKG_INSTALL docker.io netcat-openbsd &>/dev/null
  msg_ok "Installed dependencies"

  if command -v node &>/dev/null; then
    msg_ok "Node.js already installed ($(node -v))"
  else
    NODE_VERSION="24" setup_nodejs
  fi

  mkdir -p "$INSTALL_PATH"
  mkdir -p /var/lib/portracker
  fetch_and_deploy_gh_release "${APP,,}" "mostafa-wahied/portracker" "tarball"

  msg_info "Installing ${APP}"
  cd "$INSTALL_PATH/frontend"
  $STD npm ci --include=dev
  $STD npm run build

  cd "$INSTALL_PATH/backend"
  $STD npm ci --omit=dev
  mv "$INSTALL_PATH/frontend/dist" "$INSTALL_PATH/backend/public"
  msg_ok "Installed ${APP}"

  msg_info "Creating configuration"
  cp "${INSTALL_PATH}/.env.example" "${CONFIG_PATH}"
  msg_ok "Created configuration"

  msg_info "Creating service"
  create_service "$port"
  enable_service
  msg_ok "Created and started service"

  create_update_script

  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${ip}:${port}${CL}"
  msg_ok "Update with: ${BL}update_${APP,,}${CL}"
}

function create_service() {
  local port="$1"

  if [[ "$OS" == "Debian" ]]; then
    cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=${APP}
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_PATH}
EnvironmentFile=${CONFIG_PATH}
Environment=DATABASE_PATH=/var/lib/portracker/portracker.db
Environment=NODE_ENV=production
ExecStart=${BINARY_PATH}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  else
    cat <<EOF >"$SERVICE_PATH"
#!/sbin/openrc-run

name="${APP}"
description="${APP} Service"
command="${BINARY_PATH}"
command_args=""
command_background=true
directory="${INSTALL_PATH}"
pidfile="/run/${APP,,}.pid"

depend() {
    need net
}

start_pre() {
    if [ -f "${CONFIG_PATH}" ]; then
        export \$(grep -v '^#' ${CONFIG_PATH} | xargs)
    fi
}
EOF
    chmod +x "$SERVICE_PATH"
  fi
}

function create_update_script() {
  local script_name="update_${APP,,}"
  local script_path="/usr/local/bin/${script_name}"

  msg_info "Creating update script"
  cat <<UPDATEEOF >"$script_path"
#!/usr/bin/env bash
# ${APP} Update Script
# Auto-generated by community-scripts addon installer

set -e

APP="${APP}"
INSTALL_PATH="${INSTALL_PATH}"
CONFIG_PATH="${CONFIG_PATH}"

# Colors
YW='\033[33m'
GN='\033[1;92m'
RD='\033[01;31m'
BL='\033[36m'
CL='\033[m'
CM="\${GN}✔️\${CL}"
INFO="\${BL}ℹ️\${CL}"

msg_info() { echo -e "\${INFO} \${YW}\${1}...\${CL}"; }
msg_ok() { echo -e "\${CM} \${GN}\${1}\${CL}"; }

echo -e "\${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${CL}"
echo -e "\${GN}       ${APP} Update Script\${CL}"
echo -e "\${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${CL}"
echo ""

# Source tools.func for update functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func) 2>/dev/null || {
  echo -e "\${RD}Failed to load tools.func\${CL}"
  exit 1
}

if check_for_gh_release "\${APP,,}" "mostafa-wahied/portracker"; then
  msg_info "Stopping service"
  systemctl stop \${APP,,}.service &>/dev/null || true
  msg_ok "Stopped service"
  msg_info "Backing up configuration"
  cp "\$CONFIG_PATH" /tmp/\${APP,,}.env.bak 2>/dev/null || true
  msg_ok "Backed up configuration"
  fetch_and_deploy_gh_release "\${APP,,}" "mostafa-wahied/portracker" "tarball"
  msg_info "Restoring configuration"
  cp /tmp/\${APP,,}.env.bak "\$CONFIG_PATH" 2>/dev/null || true
  rm -f /tmp/\${APP,,}.env.bak
  msg_ok "Restored configuration"
  msg_info "Starting service"
  systemctl start \${APP,,}.service &>/dev/null
  msg_ok "Started service"
  echo ""
  msg_ok "\${APP} updated successfully!"
else
  msg_ok "\${APP} is already up-to-date"
fi

msg_ok "\${APP} update check completed"
UPDATEEOF

  chmod +x "$script_path"
  msg_ok "Created update script (${script_path})"
}

header_info
detect_os

IP=$(get_ip)

# Check if already installed
if [[ -f "$BINARY_PATH" ]] || [[ -d "$INSTALL_PATH" && -n "$(ls -A $INSTALL_PATH 2>/dev/null)" ]]; then
  msg_warn "${APP} is already installed."
  echo ""

  echo -n "${TAB}Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  echo -n "${TAB}Update ${APP}? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

# Fresh installation
msg_warn "${APP} is not installed."
echo ""

echo -n "${TAB}Enter port number (default: ${DEFAULT_PORT}): "
read -r PORT_INPUT
PORT="${PORT_INPUT:-$DEFAULT_PORT}"
echo ""
echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install "$PORT"
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
