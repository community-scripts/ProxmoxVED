#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RostislavDugin/postgresus

APP="Databasus"
var_tags="${var_tags:-backup;postgresql;database}"
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

  if [[ ! -f /opt/postgresus/postgresus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Databasus" "Databasus"; then
    msg_info "Stopping Databasus"
    $STD systemctl stop databasus
    msg_ok "Stopped Databasus"

    msg_info "Backing up Configuration"
    cp /opt/databasus/.env /tmp/databasus.env.bak
    msg_ok "Backed up Configuration"

    fetch_and_deploy_gh_release "databasus" "databasus/databasus" "tarball" "latest" "/opt/databasus"

    msg_info "Updating Databasus"
    cd /opt/databasus/frontend
    $STD npm ci
    $STD npm run build
    cd /opt/databasus/backend
    $STD go mod download
    $STD go build -o ../databasus ./cmd/main.go
    cd /opt/databasus/
    cp -r frontend/dist ui
    cp -r backend/migrations .
    msg_ok "Updated Databasus"

    msg_info "Restoring Configuration"
    cp /tmp/databasus.env.bak /opt/databasus/.env
    rm -f /tmp/databasus.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Databasus"
    $STD systemctl start databasus
    msg_ok "Started Databasus"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
