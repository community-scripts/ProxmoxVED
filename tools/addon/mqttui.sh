#!/usr/bin/env bash

# community-scripts ORG | MQTTUI Addon Installer
# Author: MickLesk
# License: MIT
# Source: https://github.com/terdia/mqttui

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

APP="MQTTUI"
APP_TYPE="tools"
APP_DIR="/opt/mqttui"
SERVICE="mqttui"
REPO="terdia/mqttui"
DEFAULT_PORT=8088

header_info "$APP"

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')

function is_installed() {
  [[ -d "$APP_DIR" ]] && systemctl is-active --quiet "$SERVICE"
}

function install_mqttui() {
  local port="${1:-$DEFAULT_PORT}"
  local broker="${2:-localhost}"

  UV_PYTHON="3.12" setup_uv

  fetch_and_deploy_gh_release "mqttui" "$REPO" "tarball" "latest" "$APP_DIR"

  msg_info "Setting up ${APP}"
  cd "$APP_DIR"
  $STD uv venv /opt/mqttui/.venv
  $STD uv pip install -r requirements.txt
  mkdir -p /opt/mqttui/data
  msg_ok "Set up ${APP}"

  local admin_pass
  admin_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
  local secret_key
  secret_key=$(openssl rand -hex 32)

  msg_info "Configuring ${APP}"
  cat <<EOF >"$APP_DIR/.env"
MQTTUI_ADMIN_USER=admin
MQTTUI_ADMIN_PASSWORD=${admin_pass}
SECRET_KEY=${secret_key}
MQTT_BROKER=${broker}
MQTT_PORT=1883
PORT=${port}
DB_PATH=/opt/mqttui/data/mqtt_messages.db
LOG_LEVEL=INFO
EOF
  msg_ok "Configured ${APP}"

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/${SERVICE}.service
[Unit]
Description=MQTTUI Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/.venv/bin/gunicorn --worker-class geventwebsocket.gunicorn.workers.GeventWebSocketWorker -w 1 -b 0.0.0.0:${port} wsgi:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$SERVICE"
  msg_ok "Created Service"

  msg_ok "${APP} installed at http://${IP}:${port}"
  echo -e "${TAB}Login: admin / ${admin_pass}"
  echo -e "${TAB}MQTT Broker: ${broker}:1883"
}

function uninstall_mqttui() {
  msg_info "Removing ${APP}"
  systemctl disable -q --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  rm -rf "$APP_DIR"
  msg_ok "${APP} uninstalled"
}

function update_mqttui() {
  if check_for_gh_release "mqttui" "$REPO"; then
    msg_info "Stopping ${APP}"
    systemctl stop "$SERVICE"
    msg_ok "Stopped ${APP}"

    msg_info "Backing up Data"
    cp "$APP_DIR/.env" /opt/mqttui.env.bak
    cp -r "$APP_DIR/data" /opt/mqttui_data_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mqttui" "$REPO" "tarball" "latest" "$APP_DIR"

    msg_info "Updating ${APP}"
    cd "$APP_DIR"
    $STD uv pip install -r requirements.txt
    msg_ok "Updated ${APP}"

    msg_info "Restoring Data"
    cp /opt/mqttui.env.bak "$APP_DIR/.env"
    cp -r /opt/mqttui_data_backup/. "$APP_DIR/data"
    rm -f /opt/mqttui.env.bak
    rm -rf /opt/mqttui_data_backup
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
  1) update_mqttui ;;
  2) uninstall_mqttui ;;
  3) msg_info "Cancelled" ;;
  *) msg_error "Invalid input" ;;
  esac
else
  read -r -p "Enter MQTT broker address (default: localhost): " BROKER_INPUT
  BROKER="${BROKER_INPUT:-localhost}"
  read -r -p "Enter port number (default: ${DEFAULT_PORT}): " PORT_INPUT
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  read -r -p "Install ${APP}? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  [[ "${answer,,}" =~ ^(y|yes)$ ]] && install_mqttui "$PORT" "$BROKER" || msg_info "Installation skipped"
fi
