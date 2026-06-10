#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: johnpc
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/johnpc/subsyncarr

APP="Subsyncarr"
var_tags="${var_tags:-arr;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-no}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/subsyncarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "subsyncarr" "johnpc/subsyncarr"; then
    msg_info "Stopping Service"
    systemctl stop subsyncarr
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "subsyncarr" "johnpc/subsyncarr" "tarball"

    msg_info "Updating ${APP}"
    cd /opt/subsyncarr
    $STD npm ci --ignore-scripts
    $STD npm rebuild better-sqlite3
    $STD npm run build
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start subsyncarr
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
