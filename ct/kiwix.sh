#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

APP="Kiwix"
var_tags="${var_tags:-documentation;offline}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s kiwix-tools &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT=$(cat /root/.kiwix 2>/dev/null || dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')

  msg_info "Stopping Service"
  systemctl stop kiwix-serve
  msg_ok "Stopped Service"

  msg_info "Updating Kiwix-Tools"
  $STD apt update
  $STD apt install -y --only-upgrade kiwix-tools
  RELEASE=$(dpkg -s kiwix-tools 2>/dev/null | awk '/^Version:/{print $2}')
  echo "${RELEASE}" >/root/.kiwix
  msg_ok "Updated Kiwix-Tools"

  if [[ "$CURRENT" == "$RELEASE" ]]; then
    msg_ok "Already on latest version: ${CURRENT}"
  else
    msg_ok "Updated successfully from ${CURRENT} to ${RELEASE}!"
  fi

  msg_info "Starting Service"
  systemctl start kiwix-serve
  msg_ok "Started Service"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
