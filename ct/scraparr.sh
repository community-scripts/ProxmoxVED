#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: JasonGreenC
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/thecfu/scraparr

APP="Scraparr"
var_tags="${var_tags:-arr;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
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
  if [[ ! -d /opt/scraparr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  RELEASE=$(curl -fsSL https://api.github.com/repos/thecfu/scraparr/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Services"
    systemctl stop scraparr
    msg_ok "Services Stopped"

    msg_info "Updating ${APP} to v${RELEASE}"
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/thecfu/scraparr/archive/refs/tags/v2.2.2.tar.gz" -o "$temp_file"
    tar -zxf "$temp_file"
    mv "scrappar-${RELEASE}" /opt/scrappar
    pip -q install -r /opt/scrappar/src/scrappar/requirements.txt --root-user-action=ignore
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start scraparr
    msg_ok "Started Service"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7100${CL}"
