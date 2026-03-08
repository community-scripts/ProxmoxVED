#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mcmonkeyprojects/SwarmUI

APP="SwarmUI"
var_tags="${var_tags:-ai;stable-diffusion;image-generation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-50}"
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

  if [[ ! -d /opt/swarmui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "swarmui" "mcmonkeyprojects/SwarmUI"; then
    msg_info "Stopping Service"
    systemctl stop swarmui
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/swarmui/Data /opt/swarmui_data_backup
    cp -r /opt/swarmui/Models /opt/swarmui_models_backup 2>/dev/null || true
    cp -r /opt/swarmui/Output /opt/swarmui_output_backup 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "swarmui" "mcmonkeyprojects/SwarmUI" "tarball" "latest" "/opt/swarmui"

    msg_info "Rebuilding SwarmUI"
    cd /opt/swarmui
    $STD dotnet build src/SwarmUI.csproj --configuration Release -o ./bin
    msg_ok "Rebuilt SwarmUI"

    msg_info "Restoring Data"
    cp -r /opt/swarmui_data_backup/. /opt/swarmui/Data/
    cp -r /opt/swarmui_models_backup/. /opt/swarmui/Models/ 2>/dev/null || true
    cp -r /opt/swarmui_output_backup/. /opt/swarmui/Output/ 2>/dev/null || true
    rm -rf /opt/swarmui_data_backup /opt/swarmui_models_backup /opt/swarmui_output_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start swarmui
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7801${CL}"
echo -e "${INFO}${YW} Configuration file location:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/swarmui/Data/Settings.yaml${CL}"
echo -e "${INFO}${YW} Models directory:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/swarmui/Models${CL}"
echo -e "${INFO}${YW} Note: GPU passthrough must be enabled in Proxmox for image generation.${CL}"
