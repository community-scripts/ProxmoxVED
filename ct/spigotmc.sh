#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kauezatarin
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.spigotmc.org/

APP="SpigotMC"
var_tags="game;minecraft;server"
var_cpu="2"
var_ram="4096"
var_disk="16"
var_os="debian"
var_version="13"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  
  if [[ ! -d /opt/spigotmc ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "Updates are currently not supported via this script. Please update SpigotMC manually or run BuildTools again."
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following IP:${CL}"
echo -e "${GATEWAY}${BGN} ${IP}:25565 ${CL}"
echo -e "${INFO}${YW} RCON Password has been randomly generated and saved in /opt/spigotmc/server.properties.${CL}"
