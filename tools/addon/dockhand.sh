#!/usr/bin/env bash

# community-scripts ORG | Dockhand Addon Installer
# Author: community-scripts ORG
# License: MIT
# Source: https://github.com/Finsys/dockhand

if command -v curl >/dev/null 2>&1; then
  source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
  load_functions
elif command -v wget >/dev/null 2>&1; then
  source <(wget -qO- https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
  load_functions
fi
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/tools.func)

color
catch_errors

APP="Dockhand"
APP_TYPE="tools"
APP_DIR="/opt/dockhand"
SERVICE="dockhand"
REPO="Finsys/dockhand"
DEFAULT_PORT=3000

header_info "$APP"

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')

function is_installed() {
  [[ -d "$APP_DIR" ]] && systemctl is-active --quiet "$SERVICE"
}

function build_dockhand() {
  msg_info "Building ${APP} (Patience)"
  cd "$APP_DIR"
  $STD npm install
  $STD npm run build
  mkdir -p "$APP_DIR/bin" "$APP_DIR/data"
  CGO_ENABLED=0 $STD go build -C collector -o "$APP_DIR/bin/collection-worker" .
  msg_ok "Built ${APP}"
}

function install_dockhand() {
  local port="${1:-$DEFAULT_PORT}"

  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    build-essential \
    python3
  msg_ok "Installed Dependencies"

  USE_DOCKER_REPO=true setup_docker
  NODE_VERSION="24" setup_nodejs
  setup_go

  fetch_and_deploy_gh_release "dockhand" "$REPO" "tarball" "latest" "$APP_DIR"

  build_dockhand

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/${SERVICE}.service
[Unit]
Description=Dockhand Docker Management
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
Environment=DATA_DIR=${APP_DIR}/data
Environment=HOST=0.0.0.0
Environment=PORT=${port}
ExecStart=/usr/bin/node ${APP_DIR}/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$SERVICE"
  msg_ok "Created Service"

  msg_ok "${APP} installed at http://${IP}:${port}"
  echo -e "${TAB}Open the URL and complete the setup wizard to create the admin account."
}

function uninstall_dockhand() {
  msg_info "Removing ${APP}"
  systemctl disable -q --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  rm -rf "$APP_DIR"
  msg_ok "${APP} uninstalled"
}

function update_dockhand() {
  if check_for_gh_release "dockhand" "$REPO"; then
    msg_info "Stopping ${APP}"
    systemctl stop "$SERVICE"
    msg_ok "Stopped ${APP}"

    msg_info "Backing up Data"
    cp -r "$APP_DIR/data" /opt/dockhand_data_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "dockhand" "$REPO" "tarball" "latest" "$APP_DIR"

    build_dockhand

    msg_info "Restoring Data"
    cp -r /opt/dockhand_data_backup/. "$APP_DIR/data"
    rm -rf /opt/dockhand_data_backup
    msg_ok "Restored Data"

    msg_info "Starting ${APP}"
    systemctl start "$SERVICE"
    msg_ok "Started ${APP}"
    msg_ok "${APP} updated successfully"
  else
    msg_ok "${APP} is already up-to-date"
  fi
}

if is_installed; then
  read -r -p "Update (1), Uninstall (2), Cancel (3)? [1/2/3]: " action
  action="${action//[[:space:]]/}"
  case "$action" in
  1) update_dockhand ;;
  2) uninstall_dockhand ;;
  3) msg_info "Cancelled" ;;
  *) msg_error "Invalid input" ;;
  esac
else
  read -r -p "Enter port number (default: ${DEFAULT_PORT}): " PORT_INPUT
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  read -r -p "Install ${APP}? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  [[ "${answer,,}" =~ ^(y|yes)$ ]] && install_dockhand "$PORT" || msg_info "Installation skipped"
fi
