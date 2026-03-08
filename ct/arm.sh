#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/automatic-ripping-machine/automatic-ripping-machine

APP="ARM"
var_tags="${var_tags:-media;ripping;automation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/arm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "arm" "automatic-ripping-machine/automatic-ripping-machine"; then
    msg_info "Stopping Service"
    systemctl stop armui
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/arm/arm.yaml /opt/arm_yaml.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "arm" "automatic-ripping-machine/automatic-ripping-machine" "tarball"

    msg_info "Rebuilding Python Environment"
    cd /opt/arm
    $STD uv venv /opt/arm/venv
    $STD uv pip install --python /opt/arm/venv/bin/python \
      -r <(curl -fsSL https://raw.githubusercontent.com/automatic-ripping-machine/arm-dependencies/main/requirements.txt) \
      -r requirements.txt
    msg_ok "Rebuilt Python Environment"

    msg_info "Restoring Data"
    cp /opt/arm_yaml.bak /opt/arm/arm.yaml
    chmod +x /opt/arm/scripts/thickclient/*.sh 2>/dev/null || true
    rm -f /opt/arm_yaml.bak
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start armui
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
