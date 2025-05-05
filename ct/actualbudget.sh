#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://actualbudget.org/

APP="Actual Budget"
var_tags="finance"
var_cpu="2"
var_ram="2048"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/actualbudget ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/actualbudget/actual/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ ! -f /opt/actualbudget_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/actualbudget_version.txt)" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop actualbudget
    msg_ok "${APP} Stopped"

    msg_info "Updating ${APP} to ${RELEASE}"
    NODE_VERSION="22"
    NODE_MODULE="--location=global @actual-app/sync-server"
    install_node_and_modules
    npm update -g @actual-app/sync-server
    msg_ok "Updated ${APP} to ${RELEASE}"

    systemctl daemon-reload
    systemctl start actualbudget
    msg_ok "Started ${APP}"

    msg_info "Cleaning Up"
    rm -rf /opt/actualbudget_bak
    rm -rf "/tmp/v${RELEASE}.tar.gz"
    msg_ok "Cleaned"
    msg_ok "Updated Successfully"
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
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:5006${CL}"
