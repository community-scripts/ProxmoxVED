#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stefan Knaak (corgan2222)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/291-Group/LAN-Orangutan

APP="LAN-Orangutan"
var_tags="${var_tags:-network;scanner}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
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

  if [[ ! -d /opt/lan-orangutan ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ ! -f /opt/lan-orangutan/orangutan ]]; then
    rm -f "$HOME/.lan-orangutan"
  fi

  if check_for_gh_release "lan-orangutan" "291-Group/LAN-Orangutan"; then
    msg_info "Stopping Service"
    systemctl stop lan-orangutan
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lan-orangutan" "291-Group/LAN-Orangutan" "prebuild" "latest" "/opt/lan-orangutan" "orangutan-linux-$(arch_resolve).tar.gz"

    msg_info "Updating Binary"
    if ! mv "/opt/lan-orangutan/orangutan-linux-$(arch_resolve)" /opt/lan-orangutan/orangutan; then
      rm -f "$HOME/.lan-orangutan"
      msg_error "Binary deploy failed - re-run update to retry"
      exit
    fi
    chmod +x /opt/lan-orangutan/orangutan
    msg_ok "Updated Binary"

    msg_info "Starting Service"
    systemctl start lan-orangutan
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
echo -e "${GATEWAY}${BGN}http://${IP}:291${CL}"
