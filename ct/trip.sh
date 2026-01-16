#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/itskovacs/TRIP

APP="TRIP"
var_tags="${var_tags:-maps;travel}"
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
  if [[ ! -d /opt/trip ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "trip" "itskovacs/TRIP"; then
    msg_info "Stopping Service"
    systemctl stop trip
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/trip.env /opt/trip.env.bak
    cp -r /opt/trip_storage /opt/trip_storage_backup
    msg_ok "Backed up Configuration"

    fetch_and_deploy_gh_release "trip" "itskovacs/TRIP"

    msg_info "Updating Frontend"
    cd /opt/trip/src
    $STD npm install
    $STD npm run build
    cp -r /opt/trip/src/dist/trip/browser/* /opt/trip/frontend/
    msg_ok "Updated Frontend"

    msg_info "Updating Backend"
    cd /opt/trip/backend
    $STD /opt/trip/.venv/bin/pip install --no-cache-dir -r trip/requirements.txt
    msg_ok "Updated Backend"

    msg_info "Restoring Configuration"
    cp /opt/trip.env.bak /opt/trip.env
    cp -r /opt/trip_storage_backup/. /opt/trip_storage
    rm -f /opt/trip.env.bak
    rm -rf /opt/trip_storage_backup
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start trip
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
