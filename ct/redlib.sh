#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: andrej-kocijan (Andrej Kocijan)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/redlib-org/redlib

APP="Redlib"
var_tags="${var_tags:-alpine;frontend}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.22}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_resources

  if [[ ! -d /opt/redlib ]]; then
      msg_error "No ${APP} Installation Found!"
      exit
  fi

  RELEASE=$(curl -s https://api.github.com/repos/redlib-org/redlib/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat ~/.redlib 2>/dev/null)" ]] || [[ ! -f ~/.redlib ]]; then
    msg_info "Updating Alpine Packages"
    $STD apk -U upgrade
    msg_ok "Updated Alpine Packages"

    msg_info "Stopping ${APP} Service"
    $STD rc-service redlib stop
    msg_ok "Stopped ${APP} Service"

    msg_info "Updating ${APP}"
    $STD curl -fsSL -o /tmp/redlib-x86_64-unknown-linux-musl.tar.gz \
    "https://github.com/redlib-org/redlib/releases/latest/download/redlib-x86_64-unknown-linux-musl.tar.gz"
    $STD tar -xzf /tmp/redlib-x86_64-unknown-linux-musl.tar.gz -C /opt/redlib
    $STD rm /tmp/redlib-x86_64-unknown-linux-musl.tar.gz
    msg_ok "Updated ${APP}"

    msg_info "Starting ${APP} Service"
    $STD rc-service redlib start
    msg_ok "Started ${APP} Service"

    echo "${RELEASE}" >~/.redlib
    msg_ok "Update Successful"
  else
      msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5252${CL}"
