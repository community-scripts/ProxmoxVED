#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
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

    msg_info "Backing up Data"
    cp /etc/bunkerm/bunkerm.env /opt/bunkerm.env.bak
    cp /var/lib/mosquitto/dynamic-security.json /opt/bunkerm.dynsec.bak 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bunkerm" "bunkeriot/BunkerM" "tarball"

    msg_info "Rebuilding Frontend"
    cd /opt/bunkerm/frontend
    export NODE_OPTIONS="--max-old-space-size=4096"
    $STD npm install
    $STD npm run build
    unset NODE_OPTIONS
    mkdir -p /nextjs
    cp -r /opt/bunkerm/frontend/.next/standalone/. /nextjs/
    cp -r /opt/bunkerm/frontend/.next/static /nextjs/.next/static
    cp -r /opt/bunkerm/frontend/public /nextjs/public
    msg_ok "Rebuilt Frontend"

    msg_info "Updating Backend"
    mkdir -p /app
    cp -r /opt/bunkerm/backend/app/. /app/
    touch /app/monitor/__init__.py
    msg_ok "Updated Backend"

    msg_info "Restoring Data"
    cp /opt/bunkerm.env.bak /etc/bunkerm/bunkerm.env
    cp /opt/bunkerm.dynsec.bak /var/lib/mosquitto/dynamic-security.json 2>/dev/null || true
    rm -f /opt/bunkerm.env.bak /opt/bunkerm.dynsec.bak
    msg_ok "Restored Data"

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
echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2000${CL} (Web UI)"
echo -e "${TAB}${GATEWAY}${BGN}mqtt://${IP}:1900${CL} (MQTT Broker)"
