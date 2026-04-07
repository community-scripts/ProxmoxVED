#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/emqx/MQTTX

APP="MQTTX Web"
var_tags="${var_tags:-mqtt;iot;messaging}"
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

  if [[ ! -d /opt/mqttx ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mqttx" "emqx/MQTTX"; then
    msg_info "Stopping Nginx"
    systemctl stop nginx
    msg_ok "Stopped Nginx"

    msg_info "Updating MQTTX Web"
    fetch_and_deploy_gh_release "mqttx" "emqx/MQTTX" "tarball" "latest" "/opt/mqttx"
    cd /opt/mqttx/web
    $STD yarn install --frozen-lockfile
    $STD yarn build
    msg_ok "Updated MQTTX Web"

    msg_info "Starting Nginx"
    systemctl start nginx
    msg_ok "Started Nginx"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
