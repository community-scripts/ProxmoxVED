#!/usr/bin/env bash

# community-scripts ORG | MQTTX Web Addon Installer
# Author: MickLesk
# License: MIT
# Source: https://github.com/emqx/MQTTX

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

APP="MQTTX Web"
APP_TYPE="tools"
APP_DIR="/opt/mqttx"
SERVICE="mqttx-web"
REPO="emqx/MQTTX"
DEFAULT_PORT=8095

header_info "$APP"

if ! grep -q -Ei 'debian|ubuntu' /etc/os-release; then
  msg_error "Unsupported OS. This addon supports only Debian or Ubuntu."
  exit 1
fi

IP=$(hostname -I | awk '{print $1}')

function is_installed() {
  [[ -d "$APP_DIR/web/dist" ]] && systemctl is-active --quiet "$SERVICE"
}

function install_mqttx() {
  local port="${1:-$DEFAULT_PORT}"

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  fetch_and_deploy_gh_release "mqttx" "$REPO" "tarball" "latest" "$APP_DIR"

  msg_info "Building ${APP}"
  cd "$APP_DIR/web"
  $STD yarn install --frozen-lockfile --ignore-engines
  $STD yarn build
  msg_ok "Built ${APP}"

  if ! dpkg -l nginx &>/dev/null; then
    msg_info "Installing Nginx"
    $STD apt install -y nginx
    msg_ok "Installed Nginx"
  fi

  msg_info "Configuring ${APP}"
  cat <<EOF >/etc/nginx/sites-available/mqttx-web
server {
    listen ${port};

    root ${APP_DIR}/web/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/mqttx-web /etc/nginx/sites-enabled/mqttx-web
  $STD nginx -t
  systemctl reload nginx

  cat <<EOF >/etc/systemd/system/${SERVICE}.service
[Unit]
Description=${APP} (Nginx on port ${port})
After=network.target
BindsTo=nginx.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecReload=/usr/sbin/nginx -s reload

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "$SERVICE"
  msg_ok "${APP} installed at http://${IP}:${port}"
}

function uninstall_mqttx() {
  msg_info "Removing ${APP}"
  systemctl disable -q --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  rm -f /etc/nginx/sites-enabled/mqttx-web
  rm -f /etc/nginx/sites-available/mqttx-web
  $STD nginx -t && systemctl reload nginx
  rm -rf "$APP_DIR"
  msg_ok "${APP} uninstalled"
}

function update_mqttx() {
  if check_for_gh_release "mqttx" "$REPO"; then
    msg_info "Updating ${APP}"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mqttx" "$REPO" "tarball" "latest" "$APP_DIR"
    cd "$APP_DIR/web"
    $STD yarn install --frozen-lockfile --ignore-engines
    $STD yarn build
    systemctl reload nginx
    msg_ok "${APP} updated"
  else
    msg_ok "${APP} is already up-to-date"
  fi
}

if is_installed; then
  read -r -p "Update (1), Uninstall (2), Cancel (3)? [1/2/3]: " action
  action="${action//[[:space:]]/}"
  case "$action" in
  1) update_mqttx ;;
  2) uninstall_mqttx ;;
  3) msg_info "Cancelled" ;;
  *) msg_error "Invalid input" ;;
  esac
else
  read -r -p "Enter port number (default: ${DEFAULT_PORT}): " PORT_INPUT
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  read -r -p "Install ${APP}? (y/n): " answer
  answer="${answer//[[:space:]]/}"
  [[ "${answer,,}" =~ ^(y|yes)$ ]] && install_mqttx "$PORT" || msg_info "Installation skipped"
fi
