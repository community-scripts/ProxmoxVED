#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ZimengXiong/ExcaliDash

APP="ExcaliDash"
var_tags="${var_tags:-documents;drawing;collaboration}"
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

  if [[ ! -d /opt/excalidash ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "excalidash" "ZimengXiong/ExcaliDash"; then
    msg_info "Stopping Service"
    systemctl stop excalidash
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/excalidash/backend/.env /opt/excalidash.env.bak
    cp /opt/excalidash/backend/prisma/database.db /opt/excalidash.db.bak 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "excalidash" "ZimengXiong/ExcaliDash" "tarball"

    msg_info "Rebuilding Application"
    cd /opt/excalidash/backend
    $STD npm ci
    $STD npx prisma generate
    $STD npx tsc
    cd /opt/excalidash/frontend
    $STD npm ci
    $STD npm run build
    cp -r /opt/excalidash/frontend/dist/. /var/www/excalidash/
    msg_ok "Rebuilt Application"

    msg_info "Restoring Data"
    cp /opt/excalidash.env.bak /opt/excalidash/backend/.env
    cp /opt/excalidash.db.bak /opt/excalidash/backend/prisma/database.db 2>/dev/null || true
    rm -f /opt/excalidash.env.bak /opt/excalidash.db.bak
    msg_ok "Restored Data"

    msg_info "Running Migrations"
    cd /opt/excalidash/backend
    set -a && source /opt/excalidash/backend/.env && set +a
    $STD npx prisma migrate deploy
    msg_ok "Ran Migrations"

    msg_info "Starting Service"
    systemctl start excalidash
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6767${CL}"
