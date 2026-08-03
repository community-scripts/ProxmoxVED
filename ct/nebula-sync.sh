#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/lovelaze/nebula-sync

APP="nebula-sync"
var_tags="${var_tags:-pihole;dns;sync}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
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

  if [[ ! -d /opt/nebula-sync ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nebula-sync" "lovelaze/nebula-sync"; then
    msg_info "Stopping Service"
    systemctl stop nebula-sync
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nebula-sync" "lovelaze/nebula-sync" "prebuild" "latest" "/opt/nebula-sync" "nebula-sync_*_linux_$(arch_resolve).tar.gz"
    chmod +x /opt/nebula-sync/nebula-sync

    msg_info "Starting Service"
    systemctl start nebula-sync
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
echo -e "${INFO}${YW}${APP} has no web interface.${CL}"
echo -e "${INFO}${YW}Set PRIMARY and REPLICAS in /opt/nebula-sync.env, then run:${CL}"
echo -e "${TAB}${DEFAULT}${BGN}systemctl restart nebula-sync${CL}"
