#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/YogevBokobza/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Yogev Bokobza
# License: MIT | https://github.com/YogevBokobza/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/koen01/CFSync

APP="CFSync"
var_tags="${var_tags:-3d-printing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/cfsync ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(git -C /opt/cfsync ls-remote origin HEAD 2>/dev/null | cut -f1 | head -c8)
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt 2>/dev/null)" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop cfsync
    msg_ok "Stopped ${APP}"

    msg_info "Updating ${APP} to ${RELEASE}"
    git -C /opt/cfsync pull -q
    /opt/cfsync/venv/bin/pip install -q --upgrade -r /opt/cfsync/requirements.txt
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated ${APP} to ${RELEASE}"

    msg_info "Starting ${APP}"
    systemctl start cfsync
    msg_ok "Started ${APP}"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8005${CL}"
