#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://bunkerai.dev/

APP="BunkerM"
var_tags="${var_tags:-mqtt;iot;mosquitto}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bunkerm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bunkerm" "bunkeriot/BunkerM"; then
    msg_info "Stopping Services"
    systemctl stop bunkerm
    msg_ok "Stopped Services"

    create_backup /etc/bunkerm/bunkerm.env \
      /var/lib/mosquitto/dynamic-security.json

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bunkerm" "bunkeriot/BunkerM" "tarball"

    msg_info "Rebuilding Frontend"
    cd /opt/bunkerm/frontend
    export NODE_OPTIONS="--max-old-space-size=4096"
    $STD npm install
    $STD npm install --no-save tailwindcss@3 autoprefixer tailwindcss-animate
    if [[ -f postcss.config.js ]] && grep -q 'module\.exports' postcss.config.js; then
      mv postcss.config.js postcss.config.cjs
    fi
    $STD npm run build
    unset NODE_OPTIONS
    rm -rf /usr/share/nginx/html /frontend
    mkdir -p /usr/share/nginx/html
    cp -r /opt/bunkerm/frontend/dist/. /usr/share/nginx/html/
    cp -r /opt/bunkerm/frontend /frontend
    rm -rf /frontend/node_modules
    cd /frontend/src/auth
    $STD npm install
    msg_ok "Rebuilt Frontend"

    msg_info "Updating Backend"
    mkdir -p /app
    cp -r /opt/bunkerm/backend/app/. /app/
    touch /app/monitor/__init__.py
    cp /opt/bunkerm/nginx.conf /etc/nginx/nginx.conf
    cp /opt/bunkerm/default.conf /etc/nginx/conf.d/default.conf
    sed -i 's/^user nginx;$/user www-data;/' /etc/nginx/nginx.conf
    cp /opt/bunkerm/backend/supervisord.conf /etc/supervisor/conf.d/bunkerm.conf
    msg_ok "Updated Backend"

    restore_backup
    source /etc/bunkerm/bunkerm.env
    cat <<EOF >/usr/share/nginx/html/config.js
window.__runtime_config__ = {
  API_URL: "http://${HOST_ADDRESS}:2000/api/monitor",
  DYNSEC_API_URL: "http://${HOST_ADDRESS}:2000/api/dynsec",
  AWS_BRIDGE_API_URL: "http://${HOST_ADDRESS}:2000/api/aws-bridge",
  MONITOR_API_URL: "http://${HOST_ADDRESS}:2000/api/monitor",
  EVENT_API_URL: "http://${HOST_ADDRESS}:2000/api/event",
  host: "${HOST_ADDRESS}"
};
EOF

    msg_info "Starting Services"
    systemctl start bunkerm
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URLs:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:2000${CL} (Web UI)"
echo -e "${GATEWAY}${BGN}mqtt://${IP}:1900${CL} (MQTT Broker)"
