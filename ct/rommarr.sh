#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: BlizzHacker
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/BlizzHacker/rommarr

APP="Rommarr"
var_tags="${var_tags:-arr;emulation}"
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

  if [[ ! -d /opt/rommarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rommarr" "BlizzHacker/rommarr"; then
    msg_info "Stopping Service"
    systemctl stop rommarr
    msg_ok "Stopped Service"

    # The settings file holds the request history and the release profile, so
    # it must survive an update -- it is the only state Rommarr keeps.
    create_backup /opt/rommarr/.env
    BACKUP_DIR=/opt/rommarr-data.backup create_backup /opt/rommarr/rommarr.json

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rommarr" "BlizzHacker/rommarr" "tarball" "latest" "/opt/rommarr"

    msg_info "Updating ${APP}"
    cd /opt/rommarr
    $STD /opt/rommarr/.venv/bin/pip install --upgrade -r requirements.txt
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start rommarr
    msg_ok "Started Service"
    msg_ok "Updated Successfully"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7878${CL}"
