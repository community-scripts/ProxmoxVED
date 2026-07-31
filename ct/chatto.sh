#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/chattocorp/chatto

APP="Chatto"
var_tags="${var_tags:-chat;messaging}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/chatto ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "chatto" "chattocorp/chatto"; then
    msg_info "Stopping Service"
    systemctl stop chatto
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/chatto/data /opt/chatto_data_backup
    cp /opt/chatto/chatto.toml /opt/chatto.toml.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "chatto" "chattocorp/chatto" "prebuild" "latest" "/opt/chatto" "chatto_Linux_$(arch_resolve x86_64 arm64).tar.gz"
    chmod +x /opt/chatto/chatto

    msg_info "Restoring Data"
    cp -r /opt/chatto_data_backup/. /opt/chatto/data
    cp /opt/chatto.toml.bak /opt/chatto/chatto.toml
    rm -rf /opt/chatto_data_backup /opt/chatto.toml.bak
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start chatto
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4000${CL}"
