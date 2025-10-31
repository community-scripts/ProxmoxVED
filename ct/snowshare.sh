#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: TuroYT
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/TuroYT/snowshare

APP="SnowShare"
var_tags="${var_tags:-file-sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
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
  if [[ ! -d /opt/snowshare ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "snowshare" "TuroYT/snowshare"; then
    msg_info "Downloading ${APP}"
    systemctl stop snowshare
    fetch_and_deploy_gh_release "snowshare" "TuroYT/snowshare"
    cd /opt/snowshare
    msg_ok "Downloaded ${APP}"
    msg_info "Installing ${APP}"
    npm ci
    npx prisma generate
    npm run build
    systemctl start snowshare
    msg_ok "Updated ${APP}"
    exit
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
