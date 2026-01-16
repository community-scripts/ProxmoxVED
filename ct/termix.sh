#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Termix-SSH/Termix

APP="Termix"
var_tags="${var_tags:-ssh;terminal;management}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /opt/termix ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "termix" "Termix-SSH/Termix"; then
    msg_info "Stopping ${APP}"
    systemctl stop termix
    msg_ok "Stopped ${APP}"

    msg_info "Backing up Data"
    cp -r /opt/termix/data /opt/termix_data_backup
    msg_ok "Backed up Data"

    fetch_and_deploy_gh_release "termix" "Termix-SSH/Termix"

    msg_info "Restoring Data"
    cp -r /opt/termix_data_backup/. /opt/termix/data
    rm -rf /opt/termix_data_backup
    msg_ok "Restored Data"

    msg_info "Rebuilding ${APP}"
    cd /opt/termix
    $STD npm install --ignore-scripts --force
    $STD npm rebuild better-sqlite3 --force
    $STD npm run build
    $STD npm run build:backend
    msg_ok "Rebuilt ${APP}"

    msg_info "Starting ${APP}"
    systemctl start termix
    msg_ok "Started ${APP}"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
