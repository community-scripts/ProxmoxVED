#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/bakito/adguardhome-sync

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/error_handler.func)

# Enable error handling
set -Eeuo pipefail
trap 'error_handler' ERR

# ==============================================================================
# CONFIGURATION
# ==============================================================================
APP="AdGuardHome-Sync"
APP_TYPE="addon"
INSTALL_PATH="/opt/adguardhome-sync"
CONFIG_PATH="/opt/adguardhome-sync/adguardhome-sync.yaml"
DEFAULT_PORT=8080

# Initialize all core functions (colors, formatting, icons, STD mode)
load_functions

# ==============================================================================
# HEADER
# ==============================================================================
function header_info {
  clear
  cat <<"EOF"
    ___       __                          ____  __                        _____
   /   | ____/ /___ ___  ______ __________/ / / / /___  ____ ___  ___     / ___/__  ______  _____
  / /| |/ __  / __ `/ / / / __ `/ ___/ __  / /_/ / __ \/ __ `__ \/ _ \    \__ \/ / / / __ \/ ___/
 / ___ / /_/ / /_/ / /_/ / /_/ / /  / /_/ / __  / /_/ / / / / / /  __/   ___/ / /_/ / / / / /__
/_/  |_\__,_/\__, /\__,_/\__,_/_/   \__,_/_/ /_/\____/_/ /_/ /_/\___/   /____/\__, /_/ /_/\___/
            /____/                                                           /____/
EOF
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
get_ip() {
  hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1"
}

# ==============================================================================
# OS DETECTION
# ==============================================================================
if [[ -f "/etc/alpine-release" ]]; then
  OS="Alpine"
  SERVICE_PATH="/etc/init.d/adguardhome-sync"
elif [[ -f "/etc/debian_version" ]]; then
  OS="Debian"
  SERVICE_PATH="/etc/systemd/system/adguardhome-sync.service"
else
  msg_error "Unsupported OS detected. Exiting."
  exit 1
fi

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling ${APP}"
  if [[ "$OS" == "Alpine" ]]; then
    rc-service adguardhome-sync stop &>/dev/null || true
    rc-update del adguardhome-sync &>/dev/null || true
    rm -f "$SERVICE_PATH"
  else
    systemctl disable --now adguardhome-sync.service &>/dev/null || true
    rm -f "$SERVICE_PATH"
  fi
  rm -rf "$INSTALL_PATH"
  rm -f "/usr/local/bin/update_adguardhome-sync"
  rm -f "$HOME/.adguardhome-sync"
  msg_ok "${APP} has been uninstalled"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  if check_for_gh_release "adguardhome-sync" "bakito/adguardhome-sync"; then
    msg_info "Stopping service"
    if [[ "$OS" == "Alpine" ]]; then
      rc-service adguardhome-sync stop &>/dev/null || true
    else
      systemctl stop adguardhome-sync.service &>/dev/null || true
    fi
    msg_ok "Stopped service"

    msg_info "Backing up configuration"
    cp "$CONFIG_PATH" /tmp/adguardhome-sync.yaml.bak 2>/dev/null || true
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "adguardhome-sync" "bakito/adguardhome-sync" "binary" "latest" "$INSTALL_PATH" "adguardhome-sync_linux_amd64.tar.gz"

    msg_info "Restoring configuration"
    cp /tmp/adguardhome-sync.yaml.bak "$CONFIG_PATH" 2>/dev/null || true
    rm -f /tmp/adguardhome-sync.yaml.bak
    msg_ok "Restored configuration"

    msg_info "Starting service"
    if [[ "$OS" == "Alpine" ]]; then
      rc-service adguardhome-sync start
    else
      systemctl start adguardhome-sync.service
    fi
    msg_ok "Started service"
    msg_ok "Updated successfully"
    exit
  fi
}

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  local ip
  ip=$(get_ip)

  msg_info "Downloading ${APP}"
  rm -f "$HOME/.adguardhome-sync"
  mkdir -p "$INSTALL_PATH"
  fetch_and_deploy_gh_release "adguardhome-sync" "bakito/adguardhome-sync" "binary" "latest" "$INSTALL_PATH" "adguardhome-sync_linux_amd64.tar.gz"
  chmod +x "$INSTALL_PATH/adguardhome-sync"
  msg_ok "Downloaded ${APP}"

  msg_info "Creating configuration"
  cat <<EOF >"$CONFIG_PATH"
# AdGuardHome-Sync Configuration
# Documentation: https://github.com/bakito/adguardhome-sync

# Cron expression for sync interval (e.g., every 2 hours: "0 */2 * * *")
cron: "0 */2 * * *"

# Run sync on startup
runOnStart: true

# Continue sync on errors
continueOnError: false

# Origin AdGuardHome instance (primary)
origin:
  url: "http://192.168.1.1:3000"
  # webURL: ""
  # apiPath: ""
  username: "admin"
  password: "changeme"
  # cookie: ""
  insecureSkipVerify: false
  # autoSetup: false
  # interfaceName: ""
  # dhcpServerEnabled: false

# Replica instances (one or more)
replicas:
  - url: "http://192.168.1.2:3000"
    # webURL: ""
    # apiPath: ""
    username: "admin"
    password: "changeme"
    # cookie: ""
    insecureSkipVerify: false
    # autoSetup: false
    # interfaceName: ""
    # dhcpServerEnabled: false
  # - url: "http://192.168.1.3:3000"
  #   username: "admin"
  #   password: "changeme"

# API settings (web UI)
api:
  port: ${DEFAULT_PORT}
  # username: ""
  # password: ""
  darkMode: true
  metrics:
    enabled: false
    # scrapeInterval: 30
    # queryLogLimit: 10000
  # tls:
  #   certDir: ""
  #   certName: ""
  #   keyName: ""

# Sync features (all enabled by default)
features:
  dns:
    accessLists: true
    serverConfig: true
    rewrites: true
  dhcp:
    serverConfig: true
    staticLeases: true
  generalSettings: true
  queryLogConfig: true
  statsConfig: true
  clientSettings: true
  services: true
  filters: true
  theme: true
  # tlsConfig: false
EOF
  chmod 600 "$CONFIG_PATH"
  msg_ok "Created configuration"

  msg_info "Creating service"
  if [[ "$OS" == "Alpine" ]]; then
    cat <<EOF >"$SERVICE_PATH"
#!/sbin/openrc-run

name="adguardhome-sync"
description="AdGuardHome Sync"
command="${INSTALL_PATH}/adguardhome-sync"
command_args="run --config ${CONFIG_PATH}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/adguardhome-sync.log"
error_log="/var/log/adguardhome-sync.log"

depend() {
    need net
    after firewall
}
EOF
    chmod +x "$SERVICE_PATH"
    rc-update add adguardhome-sync default
    rc-service adguardhome-sync start
  else
    cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=AdGuardHome Sync
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH}/adguardhome-sync run --config ${CONFIG_PATH}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now adguardhome-sync &>/dev/null
  fi
  msg_ok "Created and started service"

  # Create update script
  msg_info "Creating update script"
  cat <<'UPDATEEOF' >/usr/local/bin/update_adguardhome-sync
#!/usr/bin/env bash
# AdGuardHome-Sync Update Script
type=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/tools/addon/adguardhome-sync.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_adguardhome-sync
  msg_ok "Created update script (/usr/local/bin/update_adguardhome-sync)"

  echo ""
  msg_ok "${APP} installed successfully"
  msg_ok "Web UI: ${BL}http://${ip}:${DEFAULT_PORT}${CL}"
  msg_ok "Config: ${BL}${CONFIG_PATH}${CL}"
  echo ""
  msg_warn "Edit the config file to add your AdGuardHome instances!"
  msg_warn "  Origin: Your primary AdGuardHome instance"
  msg_warn "  Replicas: One or more replica instances to sync to"
}

# ==============================================================================
# MAIN
# ==============================================================================

# Handle type=update (called from update script)
if [[ "${type:-}" == "update" ]]; then
  header_info
  if [[ -d "$INSTALL_PATH" && -f "$INSTALL_PATH/adguardhome-sync" ]]; then
    update
  else
    msg_error "${APP} is not installed. Nothing to update."
    exit 1
  fi
  exit 0
fi

header_info

IP=$(get_ip)

# Check if already installed
if [[ -d "$INSTALL_PATH" && -f "$INSTALL_PATH/adguardhome-sync" ]]; then
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
echo -e "${TAB}  - AdGuardHome-Sync (Go binary)"
echo -e "${TAB}  - Systemd/OpenRC service"
echo -e "${TAB}  - Web UI on port ${DEFAULT_PORT}"
echo ""

echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
