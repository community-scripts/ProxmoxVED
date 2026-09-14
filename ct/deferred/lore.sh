#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/EpicGames/lore

APP="Lore"
var_tags="${var_tags:-vcs;git;development}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2052}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/lore ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "lore" "EpicGames/lore"; then
    msg_info "Stopping Service"
    systemctl stop lore
    msg_ok "Stopped Service"

    create_backup /opt/lore/local.toml

    fetch_and_deploy_gh_release "lore" "EpicGames/lore" "prebuild" "latest" "/opt/lore" "loreserver-*-x86_64-unknown-linux-gnu.tar.gz"

    restore_backup

    msg_info "Updating Lore Server"
    chmod +x /opt/lore/loreserver
    msg_ok "Updated Lore Server"

    msg_info "Starting Service"
    systemctl start lore
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
echo -e "${INFO}${YW} Connect the lore CLI to your server at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:41337${CL}"
echo -e "${INFO}${YW} Health check endpoint:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:41339/health_check${CL}"
