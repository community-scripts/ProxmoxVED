#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fccview/cronmaster

if ! command -v curl &>/dev/null; then
  printf "\r\e[2K%b" '\033[93m Setup Source \033[m' >&2
  apt-get update >/dev/null 2>&1
  apt-get install -y curl >/dev/null 2>&1
fi
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/error_handler.func)

# Enable error handling
set -Eeuo pipefail
trap 'error_handler' ERR

# ==============================================================================
# CONFIGURATION
# ==============================================================================
APP="CronMaster"
APP_TYPE="addon"
INSTALL_PATH="/opt/cronmaster"
CONFIG_PATH="/opt/cronmaster/.env"
DEFAULT_PORT=3000

# Initialize all core functions (colors, formatting, icons, STD mode)
load_functions

# ==============================================================================
# HEADER
# ==============================================================================
function header_info {
  clear
  cat <<"EOF"
   ______                __  ___           __
  / ____/________  ____ /  |/  /___ ______/ /____  _____
 / /   / ___/ __ \/ __ \/ /|_/ / __ `/ ___/ __/ _ \/ ___/
/ /___/ /  / /_/ / / / / /  / / /_/ (__  ) /_/  __/ /
\____/_/   \____/_/ /_/_/  /_/\__,_/____/\__/\___/_/

EOF
}

# ==============================================================================
# OS DETECTION
# ==============================================================================
if [[ -f "/etc/alpine-release" ]]; then
  msg_error "Alpine is not supported for ${APP}. Use Debian/Ubuntu."
  exit 1
elif [[ -f "/etc/debian_version" ]]; then
  OS="Debian"
  SERVICE_PATH="/etc/systemd/system/cronmaster.service"
else
  echo -e "${CROSS} Unsupported OS detected. Exiting."
  exit 1
fi

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now cronmaster.service &>/dev/null || true
  rm -f "$SERVICE_PATH"
  rm -rf "$INSTALL_PATH"
  rm -f "/usr/local/bin/update_cronmaster"
  rm -f "$HOME/.cronmaster"
  msg_ok "${APP} has been uninstalled"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  if check_for_gh_release "cronmaster" "fccview/cronmaster"; then
    msg_info "Stopping service"
    systemctl stop cronmaster.service &>/dev/null || true
    msg_ok "Stopped service"

    msg_info "Backing up configuration"
    cp "$CONFIG_PATH" /tmp/cronmaster.env.bak 2>/dev/null || true
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cronmaster" "fccview/cronmaster" "prebuild" "latest" "$INSTALL_PATH" "cronmaster_*_prebuild.tar.gz"

    msg_info "Restoring configuration"
    cp /tmp/cronmaster.env.bak "$CONFIG_PATH" 2>/dev/null || true
    rm -f /tmp/cronmaster.env.bak
    msg_ok "Restored configuration"

    msg_info "Starting service"
    systemctl start cronmaster
    msg_ok "Started service"
    msg_ok "Updated successfully"
    exit
  fi
}

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  # Setup Node.js (only installs if not present or different version)
  if command -v node &>/dev/null; then
    msg_ok "Node.js already installed ($(node -v))"
  else
    NODE_VERSION="22" setup_nodejs
  fi

  # Force fresh download by removing version cache
  rm -f "$HOME/.cronmaster"
  fetch_and_deploy_gh_release "cronmaster" "fccview/cronmaster" "prebuild" "latest" "$INSTALL_PATH" "cronmaster_*_prebuild.tar.gz"

  local AUTH_PASS
  AUTH_PASS="$(openssl rand -base64 18 | cut -c1-13)"

  msg_info "Creating configuration"
  cat <<EOF >"$CONFIG_PATH"
NODE_ENV=production
AUTH_PASSWORD=${AUTH_PASS}
PORT=${DEFAULT_PORT}
HOSTNAME=0.0.0.0
NEXT_TELEMETRY_DISABLED=1
EOF
  chmod 600 "$CONFIG_PATH"
  msg_ok "Created configuration"

  msg_info "Creating service"
  cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=CronMaster Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_PATH}
EnvironmentFile=${CONFIG_PATH}
ExecStart=/usr/bin/node ${INSTALL_PATH}/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-target.target
EOF
  systemctl enable --now cronmaster &>/dev/null
  msg_ok "Created and started service"

  # Create update script
  msg_info "Creating update script"
  cat <<'UPDATEEOF' >/usr/local/bin/update_cronmaster
#!/usr/bin/env bash
# CronMaster Update Script
type=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/tools/addon/cronmaster.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_cronmaster
  msg_ok "Created update script (/usr/local/bin/update_cronmaster)"

  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${DEFAULT_PORT}${CL}"
  msg_ok "Password: ${BL}${AUTH_PASS}${CL}"
  echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================

# Handle type=update (called from update script)
if [[ "${type:-}" == "update" ]]; then
  header_info
  if [[ -d "$INSTALL_PATH" ]]; then
    update
  else
    msg_error "${APP} is not installed. Nothing to update."
    exit 1
  fi
  exit 0
fi

header_info
get_lxc_ip

# Check if already installed
if [[ -d "$INSTALL_PATH" && -n "$(ls -A "$INSTALL_PATH" 2>/dev/null)" ]]; then
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
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - Node.js 22"
echo -e "${TAB}  - CronMaster (prebuild)"
echo ""

echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
