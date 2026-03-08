#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/caddymanager/caddymanager

APP="CaddyManager"
var_tags="${var_tags:-}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
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
  if [[ ! -d /opt/caddymanager ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "caddymanager" "caddymanager/caddymanager"; then
    msg_info "Stopping Service"
    systemctl stop caddymanager-backend
    systemctl stop caddymanager-frontend
    msg_ok "Stopped Service"

    msg_info "Backing up configuration"
    cp /opt/caddymanager/caddymanager.env /opt/
    cp /opt/caddymanager/caddymanager.sqlite /opt/
    cp /opt/caddymanager/frontend/Caddyfile /opt/
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "caddymanager" "caddymanager/caddymanager" "tarball"

    msg_info "Installing CaddyManager"
    cd /opt/caddymanager/backend
    $STD npm install
    cd /opt/caddymanager/frontend
    $STD npm install
    $STD npm run build
    msg_ok "Installed CaddyManager"

    msg_info "Restoring configuration"
    mv /opt/caddymanager.env /opt/caddymanager/
    mv /opt/caddymanager.sqlite /opt/caddymanager/
    mv -f /opt/Caddyfile /opt/caddymanager/frontend/
    msg_ok "Restored configuration"

    msg_info "Starting Service"
    systemctl start caddymanager-backend
    systemctl start caddymanager-frontend
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  cleanup_lxc
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
