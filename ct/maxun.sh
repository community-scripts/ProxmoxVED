#!/usr/bin/env bash
source <(curl -s https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

APP="Maxun"
var_tags="${var_tags:-scraper}"
var_disk="${var_disk:-7}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
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
  RELEASE=$(curl -s https://api.github.com/repos/getmaxun/maxun/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Services"
    systemctl stop maxun minio redis
    msg_ok "Services Stopped"

    msg_info "Updating ${APP} to v${RELEASE}"
    mv /opt/maxun /opt/maxun_bak
    cd /opt
    curl -fsSL "https://github.com/getmaxun/maxun/archive/refs/tags/v${RELEASE}.zip"
    unzip -q v${RELEASE}.zip
    mv maxun-${RELEASE} /opt/maxun
    mv /opt/maxun_bak/.env /opt/maxun/
    cd /opt/maxun
    npm install --legacy-peer-deps
    cd /opt/maxun/maxun-core
    npm install --legacy-peer-deps
    cd /opt/maxun
    npx playwright install --with-deps chromium
    npx playwright install-deps
    "${RELEASE}" >/opt/${APP}_version.txt

    msg_info "Starting Services"
    systemctl start minio redis maxun
    msg_ok "Started Services"

    msg_info "Cleaning Up"
    rm -rf /opt/v${RELEASE}.zip
    msg_ok "Cleaned"
    msg_ok "Updated Successfully"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5173${CL}"
