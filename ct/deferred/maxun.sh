#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

APP="Maxun"
var_tags="${var_tags:-automation;scraper}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/maxun ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # NOTE: Updates temporarily disabled due to upstream TypeScript build errors in v0.0.27+
  # The mcp-worker.ts file has type instantiation issues that prevent compilation
  # Pinned to v0.0.26 until upstream fixes the issue
  # See: https://github.com/getmaxun/maxun/releases
  msg_warn "Updates are temporarily disabled due to upstream build issues"
  msg_info "Current pinned version: v0.0.26"
  msg_info "Check https://github.com/getmaxun/maxun/releases for fixes"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW} MinIO Console:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9001${CL}"
echo -e "${INFO}${YW} Credentials saved in:${CL}"
echo -e "${TAB}/root/maxun.creds"
