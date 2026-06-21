#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jacob-masse (jacob-masse)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://flowtriq.com

APP="Flowtriq Agent"
var_tags="${var_tags:-ddos;monitoring;security;network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v ftagent &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD pip install --upgrade ftagent[full]
  msg_ok "Updated ${APP}"

  msg_info "Restarting ${APP}"
  systemctl restart ftagent
  msg_ok "Restarted ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Configure the agent:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}ftagent --setup${CL}"
echo -e "${INFO}${YW} Then start the service:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}systemctl enable --now ftagent${CL}"
echo -e "${INFO}${YW} Dashboard:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://flowtriq.com/dashboard${CL}"
