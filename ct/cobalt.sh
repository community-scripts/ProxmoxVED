#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck / Community
# Author: Community Contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/imputnet/cobalt

APP="Cobalt"
var_tags="${var_tags:-media-downloader;youtubedl;social-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/cobalt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Services"
  cd /opt/cobalt
  docker compose down
  msg_ok "Stopped Services"

  msg_info "Pulling Latest Images"
  docker compose pull
  msg_ok "Pulled Latest Images"

  msg_info "Starting Services"
  docker compose up -d
  msg_ok "Started Services"

  msg_info "Reloading Nginx"
  nginx -t && systemctl reload nginx
  msg_ok "Reloaded Nginx"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access ${APP} using:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${TAB}${GATEWAY}${BGN}API: http://${IP}:9000${CL}"
echo -e "${INFO}${YW}Edit config:${CL}"
echo -e "${TAB}cd /opt/cobalt && nano docker-compose.yml && docker compose up -d"
