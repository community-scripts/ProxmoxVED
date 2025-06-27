#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Stroopwafe1
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://leantime.io

APP="Leantime"
var_tags="${var_tags:-productivity}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
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

  # Check if installation is present | -f for file, -d for folder
  if [[ ! -d /opt/${APP} ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Creating Backup"
  mariadb-dump leantime >"/opt/${APP}_db_backup_$(date +%F).sql"
  tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" "/opt/${APP}"
  msg_ok "Backup Created"
  fetch_and_deploy_gh_release "$APP" "Leantime/leantime" "prebuild" "latest" "/opt/${APP}" Leantime-v[0-9].[0-9].[0-9].tar.gz
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/install${CL}"
