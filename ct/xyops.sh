#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: audricrosier
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://xyops.io/ | Docs: https://docs.xyops.io/

APP="xyOps"
var_tags="${var_tags:-workflow-automation;task-scheduler;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; never verified on arm64

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/xyops ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "xyops" "pixlcore/xyops"; then
    msg_info "Stopping xyOps"
    systemctl stop xyops
    msg_ok "Stopped xyOps"

    create_backup /opt/xyops/.env /opt/xyops/conf /opt/xyops/data /opt/xyops/satellite

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "xyops" "pixlcore/xyops" "tarball"

    restore_backup

    msg_info "Building xyOps"
    cd /opt/xyops
    $STD npm install
    $STD node bin/build.js dist
    msg_ok "Built xyOps"

    msg_info "Starting xyOps"
    systemctl start xyops
    msg_ok "Started xyOps"

    if [[ -d /opt/xyops/satellite ]]; then
      msg_info "Restarting Local xySat Worker"
      systemctl restart xysat
      msg_ok "Restarted Local xySat Worker"
    fi

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:5522${CL}"
echo -e "${INFO}${YW}Default login (change on first sign-in):${CL} ${BGN}admin / admin${CL}"
