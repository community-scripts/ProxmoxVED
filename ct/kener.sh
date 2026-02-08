#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: danynocz
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://kener.ing

APP="Kener"
INSTALL_DIR="/opt/kener"
SERVICE="kener"
var_tags="${var_tags:-statuspage;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-16}"
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

  if [[ ! -d $INSTALL_DIR ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Updating ${APP} from GitHub"
  cd "$INSTALL_DIR"

  $STD git pull >/tmp/kener_update.log 2>&1

  $STD npm install --quiet >/tmp/kener_update.log 2>&1

  msg_info "Restarting ${APP} service"
  $STD systemctl restart ${SERVICE}

  msg_ok "${APP} updated successfully"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} Register the first user here:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000/manage/setup${CL}"
