#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: aroldobossoni
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/decolua/9router

APP="9Router"
var_tags="${var_tags:-ai;gateway}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/9router ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "9router" "decolua/9router"; then
    msg_info "Stopping Service"
    systemctl stop 9router
    msg_ok "Stopped Service"

    create_backup /var/lib/9router

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "9router" "decolua/9router" "tarball" "latest" "/opt/9router"

    msg_info "Building 9Router"
    mkdir -p /var/lib/9router
    cd /opt/9router
    $STD npm install
    DATA_DIR=/var/lib/9router NEXT_TELEMETRY_DISABLED=1 $STD npm run build
    rm -rf /opt/9router-standalone
    mkdir -p /opt/9router-standalone/.next /opt/9router-standalone/src /opt/9router-standalone/node_modules
    cp -r .next/standalone/. /opt/9router-standalone/
    cp -r .next/static /opt/9router-standalone/.next/static
    cp -r public custom-server.js open-sse /opt/9router-standalone/
    cp -r src/mitm /opt/9router-standalone/src/mitm
    cp -r node_modules/node-forge node_modules/next /opt/9router-standalone/node_modules/
    rm -rf /opt/9router
    mv /opt/9router-standalone /opt/9router
    msg_ok "Built 9Router"

    restore_backup

    msg_info "Starting Service"
    systemctl start 9router
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:20128${CL}"
