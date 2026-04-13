#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://akaunting.com/

APP="Akaunting"
var_tags="${var_tags:-accounting;finance;erp}"
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

  if [[ ! -d /opt/akaunting ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "akaunting" "akaunting/akaunting"; then
    msg_info "Stopping Services"
    systemctl stop caddy
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/akaunting/.env /opt/akaunting.env.bak
    cp -r /opt/akaunting/storage /opt/akaunting_storage_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "akaunting" "akaunting/akaunting" "tarball"

    msg_info "Restoring Data"
    cp /opt/akaunting.env.bak /opt/akaunting/.env
    rm -f /opt/akaunting.env.bak
    cp -r /opt/akaunting_storage_backup/. /opt/akaunting/storage
    rm -rf /opt/akaunting_storage_backup
    msg_ok "Restored Data"

    msg_info "Updating Application"
    cd /opt/akaunting
    $STD composer install --no-dev --optimize-autoloader
    $STD npm install
    $STD npm run dev
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    chown -R www-data:www-data /opt/akaunting
    msg_ok "Updated Application"

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
