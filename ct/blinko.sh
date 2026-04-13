#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://blinko.space/

APP="Blinko"
var_tags="${var_tags:-notes;ai;knowledge}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/blinko ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "blinko" "blinkospace/blinko"; then
    msg_info "Stopping Service"
    systemctl stop blinko
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/blinko/.env /opt/blinko.env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "blinko" "blinkospace/blinko" "tarball"

    msg_info "Restoring Data"
    cp /opt/blinko.env.bak /opt/blinko/.env
    rm -f /opt/blinko.env.bak
    msg_ok "Restored Data"

    msg_info "Updating Application"
    cd /opt/blinko
    $STD bun install
    $STD bunx prisma migrate deploy
    $STD bun run build
    msg_ok "Updated Application"

    msg_info "Starting Service"
    systemctl start blinko
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1111${CL}"
