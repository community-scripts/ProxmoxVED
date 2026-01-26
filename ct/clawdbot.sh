#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/clawdbot/clawdbot

APP="Clawdbot"
var_tags="${var_tags:-ai;assistant}"
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

  if [[ ! -d /opt/clawdbot ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "clawdbot" "clawdbot/clawdbot"; then
    msg_info "Stopping Service"
    systemctl stop clawdbot
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/clawdbot/data /opt/clawdbot_data_backup 2>/dev/null || true
    cp -r /root/.clawdbot /root/.clawdbot_backup 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "clawdbot" "clawdbot/clawdbot"

    msg_info "Rebuilding Clawdbot"
    cd /opt/clawdbot
    $STD pnpm install --frozen-lockfile
    $STD pnpm ui:build
    msg_ok "Rebuilt Clawdbot"

    msg_info "Restoring Data"
    cp -r /opt/clawdbot_data_backup/. /opt/clawdbot/data 2>/dev/null || true
    cp -r /root/.clawdbot_backup/. /root/.clawdbot 2>/dev/null || true
    rm -rf /opt/clawdbot_data_backup /root/.clawdbot_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start clawdbot
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:18791${CL}"

