#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/kris701/ProxmoxVED/refs/heads/tubearchivist/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: [YourUserName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: [SOURCE_URL]

# App Default Values
# Name of the app (e.g. Google, Adventurelog, Apache-Guacamole"
APP="[APP_NAME]"
# Tags for Proxmox VE, maximum 2 pcs., no spaces allowed, separated by a semicolon ; (e.g. database | adblock;dhcp)
var_tags="${var_tags:-[TAGS]}"
# Number of cores (1-X) (e.g. 4) - default are 2
var_cpu="${var_cpu:-[CPU]}"
# Amount of used RAM in MB (e.g. 2048 or 4096)
var_ram="${var_ram:-[RAM]}"
# Amount of used disk space in GB (e.g. 4 or 10)
var_disk="${var_disk:-[DISK]}"
# Default OS (e.g. debian, ubuntu, alpine)
var_os="${var_os:-[OS]}"
# Default OS version (e.g. 12 for debian, 24.04 for ubuntu, 3.20 for alpine)
var_version="${var_version:-[VERSION]}"
# 1 = unprivileged container, 0 = privileged container
var_unprivileged="${var_unprivileged:-[UNPRIVILEGED]}"

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
