#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/tolgee/tolgee-platform

APP="Tolgee"
var_tags="${var_tags:-localization;i18n;developer-tools}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
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

  if [[ ! -f /opt/tolgee/tolgee.jar ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "tolgee" "tolgee/tolgee-platform"; then
    msg_info "Stopping Service"
    systemctl stop tolgee
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    if [[ -f /opt/tolgee/.env ]]; then
      cp /opt/tolgee/.env /opt/tolgee.env.bak
    fi
    if [[ -d /opt/tolgee/data ]]; then
      cp -r /opt/tolgee/data /opt/tolgee_data_backup
    fi
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "tolgee" "tolgee/tolgee-platform" "singlefile" "latest" "/opt/tolgee" "tolgee-*.jar"

    find /opt/tolgee -maxdepth 1 -type f -name 'tolgee-*.jar' -exec mv {} /opt/tolgee/tolgee.jar \;

    msg_info "Restoring Data"
    if [[ -f /opt/tolgee.env.bak ]]; then
      cp /opt/tolgee.env.bak /opt/tolgee/.env
      rm -f /opt/tolgee.env.bak
    fi
    if [[ -d /opt/tolgee_data_backup ]]; then
      cp -r /opt/tolgee_data_backup/. /opt/tolgee/data
      rm -rf /opt/tolgee_data_backup
    fi
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start tolgee
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
