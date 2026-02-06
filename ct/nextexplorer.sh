#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nxzai/nextExplorer

APP="nextExplorer"
var_tags="${var_tags:-files;documents}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
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

  if [[ ! -d /opt/nextExplorer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "nextExplorer" "nxzai/nextExplorer"; then
    msg_info "Stopping nextExplorer"
    $STD systemctl stop nextexplorer
    msg_ok "Stopped nextExplorer"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nextExplorer" "nxzai/nextExplorer" "tarball" "latest" "/opt/nextExplorer"

    msg_info "Updating nextExplorer"
    APP_DIR="/opt/nextExplorer/app"
    mkdir -p "$APP_DIR"
    cd /opt/nextExplorer/backend
    export NODE_ENV=production
    $STD npm ci
    cd /opt/nextExplorer/frontend
    unset NODE_ENV
    export NODE_ENV=development
    $STD npm ci
    $STD npm run build -- --sourcemap false
    unset NODE_ENV
    cd /opt/nextExplorer/
    mv backend/{node_modules,src,package.json} "$APP_DIR"
    mv frontend/dist/ "$APP_DIR"/src/public
    chown -R explorer:explorer "$APP_DIR" /etc/nextExplorer
    sed -i "\|version|s|$(jq -cr '.version' ${APP_DIR}/package.json)|$(cat ~/.nextexplorer)|" "$APP_DIR"/package.json
    msg_ok "Updated nextExplorer"

    msg_info "Starting nextExplorer"
    $STD systemctl start nextexplorer
    msg_ok "Started nextExplorer"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
