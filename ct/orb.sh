#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/shared/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: angusmaul
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://orb.net/

APP="Orb"
var_tags="${var_tags:-network;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
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

  if ! dpkg -s orb >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit 233
  fi

  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt install -y --only-upgrade orb
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${TAB}${GATEWAY}${BGN}To link the sensor to your orb account run:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec ${CTID} -- runuser -u orb -- orb link${CL}"
