#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://colanode.com/

APP="Colanode"
var_tags="${var_tags:-collaboration;notes;chat}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
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

  if [[ ! -d /opt/colanode ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "colanode" "colanode/colanode"; then
    msg_info "Stopping Services"
    systemctl stop colanode-server
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/colanode/.env /opt/colanode.env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "colanode" "colanode/colanode" "tarball"

    msg_info "Rebuilding Application"
    cd /opt/colanode
    export NODE_OPTIONS="--max-old-space-size=4096"
    $STD npm install
    $STD npm run build -w @colanode/core
    $STD npm run build -w @colanode/crdt
    $STD npm run build -w @colanode/server
    $STD npm run build -w @colanode/client
    $STD npm run build -w @colanode/ui
    $STD npm run build -w @colanode/web
    cp -r /opt/colanode/apps/web/dist/. /var/www/colanode/
    $STD npm prune --production
    unset NODE_OPTIONS
    msg_ok "Rebuilt Application"

    msg_info "Restoring Data"
    cp /opt/colanode.env.bak /opt/colanode/.env
    rm -f /opt/colanode.env.bak
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start colanode-server
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
echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000${CL} (Web UI - accept self-signed cert)"
echo -e "${INFO}${YW} When adding a server in the app, use:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000/config${CL}"
