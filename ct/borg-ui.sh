#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/karanhudia/borg-ui

APP="Borg-UI"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /opt/borg-ui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "borg-ui" "karanhudia/borg-ui"; then
    msg_info "Stopping Service"
    systemctl stop borg-ui
    msg_ok "Stopped Service"

    create_backup /opt/borg-ui/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "borg-ui" "karanhudia/borg-ui" "tarball"

    restore_backup

    msg_info "Building Frontend"
    cd /opt/borg-ui/frontend
    $STD npm ci
    $STD npm run build
    msg_ok "Built Frontend"

    msg_info "Updating Python Environment"
    cd /opt/borg-ui
    $STD uv venv --python 3.12 /opt/borg-ui/.venv
    $STD uv pip install --python /opt/borg-ui/.venv -r requirements.txt
    msg_ok "Updated Python Environment"

    msg_info "Starting Service"
    systemctl start borg-ui
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
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8081${CL}"
