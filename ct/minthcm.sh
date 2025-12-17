#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 minthcm
# Author: MintHCM
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/minthcm/minthcm

APP="MintHCM"
var_tags="${var_tags:-hcm}"
var_disk="${var_disk:-20}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info "$APP"
  check_container_storage
  check_container_resources

  INSTALL_DIR="/var/www/MintHCM"

  if [[ ! -d "${INSTALL_DIR}" ]] || [[ ! -d "${INSTALL_DIR}/.git" ]]; then
    msg_error "No ${APP} installation found in ${INSTALL_DIR}!"
    exit
  fi
  msg_error "Currently we don't provide an update function for this ${APP}."
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL (after DB & installer are completed):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
