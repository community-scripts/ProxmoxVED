#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Cathal O'Connor (CathalOConnorRH)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Chaptarr/chaptarr

APP="Chaptarr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function build_chaptarr() {
  cd /opt/chaptarr
  $STD dotnet restore
  $STD dotnet publish src/NzbDrone.Console/Chaptarr.Console.csproj -c Release -f net10.0 -o _output/publish
  cd frontend
  $STD yarn install
  $STD yarn build
  cp -r _output/UI /opt/chaptarr/_output/publish/
  cd /opt/chaptarr
  rm -rf _output
  mv _output/publish _output
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/chaptarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if ! check_for_gh_release "chaptarr" "Chaptarr/chaptarr"; then
    msg_ok "Already up to date"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop chaptarr
  msg_ok "Stopped Service"

  create_backup /opt/chaptarr_data

  cd /opt/chaptarr
  git fetch origin
  git reset --hard origin/develop

  build_chaptarr

  restore_backup

  msg_info "Starting Service"
  systemctl start chaptarr
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8789${CL}"
