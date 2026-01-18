#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Kofysh
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

  NODE_VERSION="24" setup_nodejs
  
  msg_info "Stopping Cobalt Services"
  systemctl stop cobalt
  msg_ok "Stopped Services"
  
  msg_info "Updating Cobalt"
  cd /opt/cobalt
  $STD git pull
  $STD pnpm install --frozen-lockfile
  $STD pnpm --filter=@imput/cobalt-api build
  $STD pnpm --filter=@imput/cobalt-web build
  msg_ok "Updated Cobalt"
  
  msg_info "Starting Cobalt Services"
  systemctl start cobalt
  msg_ok "Started Services"
  
  msg_ok "Updated successfully!"
  exit

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
