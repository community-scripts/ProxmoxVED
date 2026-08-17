#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jasmin Härkönen (jasaspi)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.valheimgame.com/

APP="Valheim"
var_tags="${var_tags:-gaming;server}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # SteamCMD and the server binary are x86_64-only
var_unprivileged="${var_unprivileged:-1}"

# Application settings the install script accepts up front (see json app_vars).
export var_server_name="${var_server_name:-}"
export var_world_name="${var_world_name:-}"
export var_server_password="${var_server_password:-}"
export var_crossplay="${var_crossplay:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/steamcmd/steamcmd.sh || ! -d /opt/valheim/server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Valheim"
  systemctl stop valheim
  msg_ok "Stopped Valheim"

  create_backup /opt/valheim/data /opt/valheim/valheim.env

  msg_info "Updating Valheim"
  if $STD runuser -u steam -- /opt/steamcmd/steamcmd.sh \
    +force_install_dir /opt/valheim/server \
    +login anonymous \
    +app_update 896660 validate \
    +quit; then
    msg_ok "Updated Valheim"
  else
    restore_backup
    systemctl start valheim
    msg_error "Failed to update Valheim"
    exit 1
  fi

  restore_backup

  msg_info "Starting Valheim"
  systemctl start valheim
  msg_ok "Started Valheim"
  msg_ok "Updated Successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Join the server in Valheim:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:2456${CL}"
echo -e "${INFO}${YW} Required ports:${CL} ${BGN}2456-2457 UDP${CL}"
echo -e "${INFO}${YW} Server settings:${CL} ${BGN}/opt/valheim/valheim.env${CL} (password included)"
