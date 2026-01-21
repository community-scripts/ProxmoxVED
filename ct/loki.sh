#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/aBat001795/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: hoholms
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/grafana/loki

APP="Loki"
var_tags="${var_tags:-monitoring;logs}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
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

  if ! dpkg -s loki >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  msg_info "Stopping Loki"
  systemctl stop loki
  systemctl stop promtail
  msg_ok "Stopped Loki"

  msg_info "Updating Loki"
  $STD apt update
  $STD apt --only-upgrade install -y loki
  $STD apt --only-upgrade install -y promtail
  msg_ok "Updated Loki"

  msg_info "Starting Loki"
  systemctl start loki
  systemctl start promtail
  msg_ok "Started Loki"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3100${CL}\n"
echo -e "${INFO}${YW} Access promtail using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9080${CL}"
