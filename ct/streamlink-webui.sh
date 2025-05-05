#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/CrazyWolf13/streamlink-webui

# App Default Values
APP="streamlink-webui"
var_tags="download;streaming"
var_cpu="2"
var_ram="2048"
var_disk="5"
var_os="debian"
var_version="12"
var_unprivileged="1"
# 1 = unprivileged container, 0 = privileged container

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/streamlink-webui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/CrazyWolf13/streamlink-webui/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop ${APP}
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    rm -rf /opt/${APP}
    fetch_and_deploy_gh_release "CrazyWolf13/streamlink-webui"
    cd /opt/"${APPLICATION}"/backend/src
    pip install -r requirements.txt
    cd ../../frontend/src
    npm install
    yarn build
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start ${APP}
    msg_ok "Started $APP"

    msg_ok "Update Successful"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:[PORT]${CL}"
