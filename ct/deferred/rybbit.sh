#!/usr/bin/env bash
source <(curl -fsSL "${PVE_SCRIPT_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rybbit-io/rybbit

APP="Rybbit"
var_tags="${var_tags:-analytics}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
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
  if [[ ! -d /var ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Rybbit LXC"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated Rybbit LXC"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
msg_custom "🚀" "${GN}" "${APP} setup has been successfully initialized!"
