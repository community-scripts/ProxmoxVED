#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/naiba/bonds | Github: https://github.com/naiba/bonds

APP="Bonds"
var_tags="${var_tags:-erp}"
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
  if [[ ! -f /etc/systemd/system/bonds.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  
  RELEASE_TAG=$(curl -s https://api.github.com/repos/naiba/bonds/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
  ARCH=$(arch_resolve "amd64" "arm64")

  msg_info "Stopping Service"
  systemctl stop bonds
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  curl -fsSL "https://github.com/naiba/bonds/releases/download/${RELEASE_TAG}/bonds-server-linux-${ARCH}.tar.gz" | tar -xz -C /opt/bonds
  chmod +x /opt/bonds/bonds-server
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start bonds
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
