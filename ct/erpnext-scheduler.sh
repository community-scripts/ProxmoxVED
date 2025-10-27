#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: gpt-5-codex
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/frappe/erpnext

APP="ERPNext Scheduler"
var_tags="${var_tags:-erp;scheduler}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
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

  if [[ ! -d /home/frappe/frappe-bench ]]; then
    msg_error "No ERPNext Scheduler Installation Found!"
    exit
  fi

  msg_error "Update automation for ${APP} is not available yet."
  msg_info "Please update the shared bench and restart scheduler workers."
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Scheduler will execute background jobs using the shared bench instance.${CL}"
