#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fleetdm/fleet

APP="Fleet"
var_tags="${var_tags:-monitoring;device-management;security}"
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

  if [[ ! -f /opt/fleet/fleet ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "fleet" "fleetdm/fleet"; then
    msg_info "Stopping Service"
    systemctl stop fleet
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "fleet" "fleetdm/fleet" "prebuild" "latest" "/opt/fleet" "fleet_v*_linux.tar.gz"
    chmod +x /opt/fleet/fleet

    msg_info "Running Database Migrations"
    set -a && source /opt/fleet/.env && set +a
    $STD /opt/fleet/fleet prepare db
    msg_ok "Ran Database Migrations"

    msg_info "Starting Service"
    systemctl start fleet
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
