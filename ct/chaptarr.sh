#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/shared/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: aodesser
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Chaptarr/chaptarr

APP="Chaptarr"
var_tags="${var_tags:-arr;audiobooks;books}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
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

  if [[ ! -d /opt/chaptarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if GH_INCLUDE_PRERELEASE=1 check_for_gh_release "chaptarr" "Chaptarr/chaptarr"; then
    msg_info "Stopping Service"
    systemctl stop chaptarr
    msg_ok "Stopped Service"

    GH_INCLUDE_PRERELEASE=1 CLEAN_INSTALL=1 fetch_and_deploy_gh_release "chaptarr" "Chaptarr/chaptarr" "tarball"

    msg_info "Building Chaptarr (Patience)"
    cd /opt/chaptarr
    $STD yarn install --frozen-lockfile
    $STD yarn build
    rm -rf /opt/chaptarr_app
    $STD dotnet publish src/NzbDrone.Console/Chaptarr.Console.csproj -c Release -f net10.0 -o /opt/chaptarr_app /p:UseAppHost=false
    mkdir -p /opt/chaptarr_app/UI
    cp -r _output/UI/* /opt/chaptarr_app/UI/
    msg_ok "Built Chaptarr"

    msg_info "Starting Service"
    systemctl start chaptarr
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8789${CL}"
