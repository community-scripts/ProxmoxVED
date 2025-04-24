#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/steveiliop56/tinyauth

APP="Alpine-tinyauth"
var_tags="${var_tags:-alpine;auth}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.21}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  if [ ! -d /opt/tinyauth ]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi
  msg_info "Updating Alpine Packages"
  $STD apk update
  $STD apk upgrade
  msg_ok "Updated Alpine Packages"

  msg_info "Updating tinyauth"
  $STD apk upgrade tinyauth
  msg_ok "Updated tinyauth"

  msg_info "Restarting tinyauth"
  $STD rc-service tinyauth restart
  msg_ok "Restarted tinyauth"

  exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:xxxx${CL}"
