#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/Hermandev07/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/Hermandev07/ProxmoxVED/raw/main/LICENSE
# Source: https://www.haproxy.com/

APP="HAProxy"
var_tags="${var_tags:-proxy;load-balancer}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/haproxy/haproxy.cfg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating HAProxy"
  $STD apt update
  $STD apt upgrade -y haproxy
  msg_ok "Updated HAProxy"

  msg_info "Validating HAProxy configuration"
  $STD haproxy -c -f /etc/haproxy/haproxy.cfg
  msg_ok "Validated HAProxy configuration"

  msg_info "Reloading HAProxy"
  systemctl reload haproxy
  msg_ok "Reloaded HAProxy"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} HAProxy stats are available at:${CL}"
echo -e "${TAB}${BGN}http://${IP}:8404${CL}"
echo -e "${INFO}${YW} Login:${CL}"
echo -e "${TAB}${BGN}admin/admin${CL}"
