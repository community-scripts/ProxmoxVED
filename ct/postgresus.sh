#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RostislavDugin/postgresus

APP="Postgresus"
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

  if check_for_gh_release "RostislavDugin" "postgresus"; then
    msg_info "Stopping Postgresus"
    $STD systemctl stop postgresus
    msg_ok "Stopped Postgresus"

    msg_info "Backing up Configuration"
    cp /opt/postgresus/.env /tmp/postgresus.env.bak
    msg_ok "Backed up Configuration"

    fetch_and_deploy_gh_release "postgresus" "RostislavDugin/postgresus" "tarball" "v${RELEASE}" "/opt/postgresus"

    msg_info "Updating Postgresus"
    cd /opt/postgresus/frontend
    $STD npm ci
    $STD npm run build
    cd /opt/postgresus/backend
    $STD go mod download
    $STD go build -o ../postgresus ./cmd/main.go
    cd /opt/postgresus/
    cp -r frontend/dist ui
    cp -r backend/migrations .
    msg_ok "Updated Postgresus"

    msg_info "Restoring Configuration"
    cp /tmp/postgresus.env.bak /opt/postgresus/.env
    rm -f /tmp/postgresus.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Postgresus"
    $STD systemctl start postgresus
    msg_ok "Started Postgresus"
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
