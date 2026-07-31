#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://logto.io/

APP="Logto"
var_tags="${var_tags:-auth;identity;oidc}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-no}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/logto ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "logto" "logto-io/logto"; then
    msg_info "Stopping Service"
    systemctl stop logto
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/logto/.env /opt/logto.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "logto" "logto-io/logto" "prebuild" "latest" "/opt/logto" "logto.tar.gz"

    msg_info "Restoring Configuration"
    cp /opt/logto.env.bak /opt/logto/.env
    rm -f /opt/logto.env.bak
    msg_ok "Restored Configuration"

    msg_info "Applying Database Migrations"
    cd /opt/logto
    set -o allexport
    source /opt/logto/.env
    set +o allexport
    $STD npm run cli db alteration deploy
    msg_ok "Applied Database Migrations"

    msg_info "Starting Service"
    systemctl start logto
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
echo -e "${GATEWAY}${BGN}http://${IP}:3002${CL}"
