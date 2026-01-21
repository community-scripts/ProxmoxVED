#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/aBat001795/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://petio.tv/

APP="Petio"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Petio ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Pepito"
  systemctl stop petio
  curl -fsSL https://petio.tv/releases/latest -o petio-latest.zip
  $STD unzip petio-latest.zip -d /opt/Petio
  systemctl start petio
  msg_ok "Updated Pepito"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7777${CL}"
