#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: chrnie
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://icinga.com/

APP="Icinga"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="0"
# need privileges for ping checks
# ping: socktype: SOCK_RAW
# ping: socket: Operation not permitted
# ping: => missing cap_net_raw+p capability or setuid


header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/sbin/icinga2 ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Icinga"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Icinga"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/icingaweb2 for icingaweb and Port 5665 for icinga2 api.${CL}"
