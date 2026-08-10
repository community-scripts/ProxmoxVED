#!/usr/bin/env bash

# community-scripts ORG | Headplane Addon Installer
# Author: MickLesk (CanbiZ)
# License: MIT
# Source: https://github.com/tale/headplane

if command -v curl >/dev/null 2>&1; then
  source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/core.func)
  load_functions
elif command -v wget >/dev/null 2>&1; then
  source <(wget -qO- ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/core.func)
  load_functions
fi
source <(curl -fsSL ${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/tools.func)

color
catch_errors

APP="Headplane"
APP_TYPE="tools"
APP_DIR="/opt/headplane"
DATA_DIR="/opt/headplane_data"
SERVICE="headplane"
REPO="tale/headplane"

header_info "$APP"

if ! command -v headscale >/dev/null || ! systemctl is-active --quiet headscale; then
  msg_error "Headscale is not installed or not running. Install the Headscale LXC first, then run this addon inside it."
  exit 1
fi

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

MEM_MB=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
if ((MEM_MB < 2048)); then
  msg_error "Insufficient memory: ${MEM_MB} MB detected. At least 2048 MB RAM is required to build Headplane."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')
HEADSCALE_PORT=$(awk '/^listen_addr:/ {print $2}' /etc/headscale/config.yaml 2>/dev/null | tr -d '"' | awk -F: '{print $NF}')
HEADSCALE_PORT="${HEADSCALE_PORT:-8080}"

function is_installed() {
  [[ -d "$APP_DIR" ]] && systemctl is-active --quiet "$SERVICE"
}

function build_headplane() {
  cd "$APP_DIR" || exit 1
  $STD pnpm install --frozen-lockfile
  $STD pnpm build
}

function install_ui() {
  NODE_VERSION="24" NODE_MODULE="pnpm@^10" setup_nodejs
  fetch_and_deploy_gh_release "headplane" "$REPO" "tarball"

  msg_info "Building ${APP}"
  build_headplane
  msg_ok "Built ${APP}"

  msg_info "Configuring ${APP}"
  mkdir -p "$DATA_DIR"
  API_KEY=$(headscale apikeys create --expiration 999d 2>/dev/null | tail -n1)
  cat <<EOF >"${DATA_DIR}/config.yaml"
server:
  host: "0.0.0.0"
  port: 3000
  base_url: "http://${IP}:3000"
  cookie_secret: "$(openssl rand -base64 24 | cut -c1-32)"
  cookie_secure: false
  data_path: "${DATA_DIR}"

headscale:
  url: "http://127.0.0.1:${HEADSCALE_PORT}"
  config_path: "/etc/headscale/config.yaml"
  api_key: "${API_KEY}"

integration:
  agent:
    enabled: false
  proc:
    enabled: true
EOF
  chmod 600 "${DATA_DIR}/config.yaml"

  cat <<EOF >/etc/systemd/system/${SERVICE}.service
[Unit]
Description=${APP} Service
After=network.target headscale.service
Requires=headscale.service

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
Environment=HEADPLANE_CONFIG_PATH=${DATA_DIR}/config.yaml
ExecStart=/usr/bin/node ${APP_DIR}/build/server/index.js
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=${SERVICE}

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now "$SERVICE"
  msg_ok "${APP} installed at http://${IP}:3000/admin"
}

function uninstall_ui() {
  msg_info "Stopping ${APP}"
  systemctl disable -q --now "$SERVICE"
  rm -f "/etc/systemd/system/${SERVICE}.service"
  systemctl daemon-reexec

  msg_info "Removing files"
  rm -rf "$APP_DIR" "$DATA_DIR"
  msg_ok "${APP} uninstalled"
}

function update_ui() {
  if check_for_gh_release "headplane" "$REPO"; then
    msg_info "Stopping ${APP}"
    systemctl stop "$SERVICE"
    msg_ok "Stopped ${APP}"

    NODE_VERSION="24" NODE_MODULE="pnpm@^10" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "headplane" "$REPO" "tarball"

    msg_info "Building ${APP}"
    build_headplane
    msg_ok "Built ${APP}"

    systemctl start "$SERVICE"
    msg_ok "${APP} updated"
  else
    msg_ok "${APP} is already up-to-date"
  fi
}

if is_installed; then
  read -r -p "Update (1), Uninstall (2), Cancel (3)? [1/2/3]: " action
  action="${action//[[:space:]]/}"
  case "$action" in
  1) update_ui ;;
  2) uninstall_ui ;;
  3) msg_info "Cancelled" ;;
  *) msg_error "Invalid input" ;;
  esac
else
  read -r -p "Install ${APP}? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  [[ "${answer,,}" =~ ^(y|yes)$ ]] && install_ui || msg_info "Installation skipped"
fi
