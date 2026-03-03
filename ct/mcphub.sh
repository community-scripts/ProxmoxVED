#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/samanhappy/mcphub | Docs: https://docs.mcphubx.com/

APP="MCPHub"
var_tags="${var_tags:-ai;automation;tooling}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/mcphub.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  NODE_VERSION="22" setup_nodejs

  msg_info "Updating MCPHub"
  systemctl stop mcphub
  if ! $STD npm update -g @samanhappy/mcphub; then
    if systemctl start mcphub; then
      msg_error "Failed to update MCPHub. Service restart succeeded."
    else
      msg_error "Failed to update MCPHub and failed to restart service."
    fi
    exit 1
  fi

  if ! systemctl start mcphub; then
    msg_error "MCPHub updated, but failed to start service."
    exit 1
  fi

  if ! systemctl is-active -q mcphub; then
    msg_error "MCPHub updated, but service is not running."
    exit 1
  fi

  msg_ok "Updated MCPHub"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
