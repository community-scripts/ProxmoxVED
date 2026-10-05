#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/logto-io/logto

APP="Logto"
var_tags="${var_tags:-auth;sso;oidc}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

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
    msg_info "Stopping Logto"
    systemctl stop logto
    msg_ok "Stopped Logto"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "logto" "logto-io/logto" "prebuild" "latest" "/opt/logto" "logto.tar.gz"

    msg_info "Migrating Logto Database"
    cd /opt/logto
    CI=true $STD npm run alteration deploy latest -- --env /opt/logto_data/.env
    msg_ok "Migrated Logto Database"

    msg_info "Starting Logto"
    systemctl start logto
    msg_ok "Started Logto"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Create the first admin account in the Admin Console:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}:3002${CL}"
echo -e "${INFO}${YW}Sign-in endpoint for your apps (OIDC issuer: /oidc):${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}:3001${CL}"
