#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Sportarr/Sportarr

APP="Sportarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-1}"
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
  if [[ ! -d /opt/sportarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "sportarr" "Sportarr/Sportarr"; then
    msg_info "Stopping Sportarr Service"
    systemctl stop sportarr
    msg_ok "Stopped Sportarr Service"

    msg_info "Creating Backup"

    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "sportarr" "Sportarr/Sportarr" "prebuild" "latest" "/opt/sportarr" "Sportarr-linux-x64-*.tar.gz"

    msg_info "Updating sportarr"

    msg_ok "Updated sportarr"

    msg_info "Restoring Backup"

    msg_ok "Restored Backup"

    msg_info "Starting Sportarr Service"
    systemctl start sportarr
    msg_ok "Started Sportarr Service"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1867${CL}"
