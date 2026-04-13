#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://matomo.org/

APP="Matomo"
var_tags="${var_tags:-analytics;tracking;privacy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
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

  if [[ ! -d /opt/matomo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "matomo" "matomo-org/matomo"; then
    msg_info "Stopping Services"
    systemctl stop caddy
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/matomo/config/config.ini.php /opt/matomo_config.bak
    cp -r /opt/matomo/misc/user /opt/matomo_user_backup 2>/dev/null
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "matomo" "matomo-org/matomo" "prebuild" "latest" "/opt/matomo" "matomo-*.zip"

    msg_info "Restoring Data"
    cp /opt/matomo_config.bak /opt/matomo/config/config.ini.php
    cp -r /opt/matomo_user_backup/. /opt/matomo/misc/user 2>/dev/null
    rm -f /opt/matomo_config.bak
    rm -rf /opt/matomo_user_backup
    chown -R www-data:www-data /opt/matomo
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start caddy
    msg_ok "Started Services"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
