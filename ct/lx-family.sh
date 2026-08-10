#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/shared/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/build.func")
# Copyright (c) 2026 community-scripts ORG
# Author: LaxXx Lab (laxxx-lab)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/laxxx-lab/lx-family-planner

APP="LX Family"
var_tags="${var_tags:-family;calendar;chores;shopping;self-hosted}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; not verified on bare-metal ARM yet
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function build_lx_family() {
  cd /opt/lx-family
  msg_info "Installing LX Family"
  $STD npm ci
  $STD npm run build
  msg_ok "Installed LX Family"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/lx-family ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "lx-family" "laxxx-lab/lx-family-planner"; then
    msg_info "Stopping Service"
    systemctl stop lx-family
    msg_ok "Stopped Service"

    create_backup /opt/lx-family/.env /opt/lx-family/data /opt/lx-family/backups

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lx-family" "laxxx-lab/lx-family-planner" "tarball"

    restore_backup
    build_lx_family

    msg_info "Starting Service"
    systemctl start lx-family
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
echo -e "${GATEWAY}${BGN}http://${IP}:3001${CL}"
