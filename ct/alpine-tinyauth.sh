#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/steveiliop56/tinyauth

APP="tinyauth"
var_tags="${var_tags:-alpine;auth}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
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
  $STD apk update && apk upgrade
  msg_ok "Updated Alpine Packages"

  echo "DEBUG: CT_TYPE before update_script=${CT_TYPE:-UNDEFINED}"
  echo "DEBUG: var_unprivileged=${var_unprivileged:-UNDEFINED}"

  msg_info "Updating tinyauth"
  $STD apk upgrade tinyauth
  msg_ok "Updated tinyauth"

  msg_info "Restarting tinyauth"
  $STD rc-service tinyauth restart
  msg_ok "Restarted tinyauth"
}

start
build_container
description

msg_ok "Completed Successfully!\n"
