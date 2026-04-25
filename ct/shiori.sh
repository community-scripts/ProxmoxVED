#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot (GPT-5.3-Codex)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/go-shiori/shiori

APP="Shiori"
var_tags="${var_tags:-bookmarks;read-it-later;notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
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

  if [[ ! -d /opt/shiori ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "shiori" "go-shiori/shiori"; then
    msg_info "Stopping Service"
    systemctl stop shiori
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    if [[ -d /opt/shiori/data ]]; then
      cp -r /opt/shiori/data /opt/shiori_data_backup
    fi
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "shiori" "go-shiori/shiori" "prebuild" "latest" "/opt/shiori" "*Linux_x86_64.tar.gz"

    chmod +x /opt/shiori/shiori

    msg_info "Restoring Data"
    if [[ -d /opt/shiori_data_backup ]]; then
      cp -r /opt/shiori_data_backup/. /opt/shiori/data
      rm -rf /opt/shiori_data_backup
    fi
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start shiori
    msg_ok "Started Service"
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
