#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/kris701/ProxmoxVED/refs/heads/tubearchivist/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Kristian Skov
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.tubearchivist.com/

# App Default Values
APP="Tube Archivist"
var_tags="${var_tags:-web}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Pulling docker image"
  docker compose pull
  msg_ok "Docker image pulled"

  msg_info "Starting docker container"
  docker compose up -d
  msg_ok "Container started"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:[PORT]${CL}"
