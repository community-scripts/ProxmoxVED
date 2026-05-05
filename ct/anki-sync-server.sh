#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/EsBaTix/ProxmoxVED/main/misc/build.func)
# Copyright (c) community-scripts ORG
# Author: EsBaTix
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.ankiweb.net/sync-server.html

APP="anki-sync-server"
var_tags="${var_tags:-anki}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
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
  if [[ ! -f /etc/systemd/system/anki-sync-server.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping ${APP}"
  systemctl stop anki-sync-server
  msg_ok "Stopped ${APP}"

  msg_info "Updating LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_info "Updated LXC"

  msg_info "Updating ${APP}"
  $STD runuser -u anki -- \
    /opt/anki/venv/bin/pip install --upgrade anki
  msg_ok "Updated ${APP}"

  msg_info "Starting ${APP}"
  systemctl start anki-sync-server
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"