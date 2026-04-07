#!/usr/bin/env bash

# community-scripts ORG | Mongo Express Addon Installer
# Author: MickLesk
# License: MIT
# Source: https://github.com/mongo-express/mongo-express

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

APP="Mongo Express"
APP_TYPE="tools"
APP_DIR="/opt/mongo-express"
SERVICE="mongo-express"
REPO="mongo-express/mongo-express"
DEFAULT_PORT=8081

header_info "$APP"

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')

function is_installed() {
  [[ -d "$APP_DIR" ]] && systemctl is-active --quiet "$SERVICE"
}

function install_mongo_express() {
  local port="${1:-$DEFAULT_PORT}"
  local mongo_url="${2:-mongodb://localhost:27017}"

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  fetch_and_deploy_gh_release "mongo-express" "$REPO" "tarball" "latest" "$APP_DIR"

  msg_info "Building ${APP}"
  cd "$APP_DIR"
  $STD yarn install
  $STD yarn build
  rm -rf lib/scripts
  msg_ok "Built ${APP}"

  local cookie_secret
  local session_secret
  cookie_secret=$(openssl rand -base64 32)
  session_secret=$(openssl rand -base64 32)

  msg_info "Configuring ${APP}"
  cat <<EOF >"$APP_DIR/.env"
ME_CONFIG_MONGODB_URL=${mongo_url}
ME_CONFIG_MONGODB_ENABLE_ADMIN=true
ME_CONFIG_BASICAUTH_ENABLED=true
ME_CONFIG_BASICAUTH_USERNAME=admin
ME_CONFIG_BASICAUTH_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
ME_CONFIG_SITE_COOKIESECRET=${cookie_secret}
ME_CONFIG_SITE_SESSIONSECRET=${session_secret}
VCAP_APP_HOST=0.0.0.0
PORT=${port}
EOF
  msg_ok "Configured ${APP}"

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/${SERVICE}.service
[Unit]
Description=Mongo Express
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
Environment=NODE_ENV=production
ExecStart=/usr/bin/node app.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$SERVICE"
  msg_ok "Created Service"

  local me_pass
  me_pass=$(grep ME_CONFIG_BASICAUTH_PASSWORD "$APP_DIR/.env" | cut -d= -f2)
  msg_ok "${APP} installed at http://${IP}:${port}"
  echo -e "${TAB}Login: admin / ${me_pass}"
  echo -e "${TAB}MongoDB URL: ${mongo_url}"
}

function uninstall_mongo_express() {
  msg_info "Removing ${APP}"
  systemctl disable -q --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  rm -rf "$APP_DIR"
  msg_ok "${APP} uninstalled"
}

function update_mongo_express() {
  if check_for_gh_release "mongo-express" "$REPO"; then
    msg_info "Stopping ${APP}"
    systemctl stop "$SERVICE"
    msg_ok "Stopped ${APP}"

    msg_info "Backing up Configuration"
    cp "$APP_DIR/.env" /opt/mongo-express.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mongo-express" "$REPO" "tarball" "latest" "$APP_DIR"

    msg_info "Building ${APP}"
    cd "$APP_DIR"
    $STD yarn install
    $STD yarn build
    rm -rf lib/scripts
    msg_ok "Built ${APP}"

    msg_info "Restoring Configuration"
    cp /opt/mongo-express.env.bak "$APP_DIR/.env"
    rm -f /opt/mongo-express.env.bak
    msg_ok "Restored Configuration"

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
  1) update_mongo_express ;;
  2) uninstall_mongo_express ;;
  3) msg_info "Cancelled" ;;
  *) msg_error "Invalid input" ;;
  esac
else
  read -r -p "Enter MongoDB connection URL (default: mongodb://localhost:27017): " MONGO_URL_INPUT
  MONGO_URL="${MONGO_URL_INPUT:-mongodb://localhost:27017}"
  read -r -p "Enter port number (default: ${DEFAULT_PORT}): " PORT_INPUT
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  read -r -p "Install ${APP}? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  [[ "${answer,,}" =~ ^(y|yes)$ ]] && install_mongo_express "$PORT" "$MONGO_URL" || msg_info "Installation skipped"
fi
