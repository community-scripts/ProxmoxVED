#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
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
  if systemctl is-active --quiet promtail 2>/dev/null || dpkg -s promtail >/dev/null 2>&1; then
    systemctl stop promtail
  fi
  msg_ok "Stopped Loki"

  msg_info "Updating Loki"
  $STD apt-get update
  $STD apt-get --only-upgrade install -y loki
  if dpkg -s promtail >/dev/null 2>&1; then
    $STD apt-get --only-upgrade install -y promtail
  fi
  msg_ok "Updated Loki"

  msg_info "Starting Loki"
  systemctl start loki
  if dpkg -s promtail >/dev/null 2>&1; then
    systemctl start promtail
  fi
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
