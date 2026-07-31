#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: PawelSzymanski89
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/PawelSzymanski89/valheim-proxmox

APP="Valheim"
var_tags="${var_tags:-game;valheim}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/valheim ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Two things update independently: the game comes from Steam, the panel from GitHub.
  msg_info "Checking Steam for a new game build"
  APPID=896660
  INSTALLED=$(awk -F'"' '/"buildid"/{print $4; exit}' /opt/valheim/server/steamapps/appmanifest_${APPID}.acf 2>/dev/null)
  LATEST=$(runuser -u valheim -- env HOME=/opt/valheim /opt/valheim/steamcmd/steamcmd.sh \
    +login anonymous +app_info_update 1 +app_info_print ${APPID} +quit 2>/dev/null |
    sed -n '/"branches"/,/^}/p' | sed -n '/"public"/,/}/p' | grep -m1 '"buildid"' | grep -oE '[0-9]+')
  if [[ -n "$LATEST" && "$INSTALLED" != "$LATEST" ]]; then
    msg_ok "New build ${LATEST} available"
    msg_info "Stopping ${APP}"
    systemctl stop valheim
    msg_ok "Stopped ${APP}"

    msg_info "Updating game files (this pulls ~1.5 GB)"
    $STD runuser -u valheim -- env HOME=/opt/valheim /opt/valheim/steamcmd/steamcmd.sh \
      +force_install_dir /opt/valheim/server +login anonymous +app_update ${APPID} validate +quit
    msg_ok "Updated game files"

    msg_info "Starting ${APP}"
    systemctl start valheim
    msg_ok "Started ${APP}"
  else
    msg_ok "Game is up to date (build ${INSTALLED:-unknown})"
  fi

  if check_for_gh_release "valheim-panel" "PawelSzymanski89/valheim-proxmox"; then
    msg_info "Stopping Panel"
    systemctl stop valheim-panel
    msg_ok "Stopped Panel"

    # panel.env holds the login and port, server.env the game settings - neither is shipped
    create_backup /opt/valheim/panel.env /opt/valheim/server.env

    fetch_and_deploy_gh_release "valheim-panel" "PawelSzymanski89/valheim-proxmox" "prebuild" "latest" "/opt/valheim/panel" "panel.tar.gz"

    msg_info "Updating Panel Dependencies"
    $STD uv pip install --python /opt/valheim/panel/.venv/bin/python --upgrade fastapi "uvicorn[standard]" pyyaml
    msg_ok "Updated Panel Dependencies"

    msg_info "Starting Panel"
    systemctl start valheim-panel
    msg_ok "Started Panel"
    msg_ok "Updated Successfully"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the panel using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:2460${CL}"
echo -e "${INFO}${YW}Log in with admin / valheim123 and change it in Settings.${CL}"
echo -e "${INFO}${YW}Players join at ${IP}:2456 - forward UDP 2456-2458 for internet access.${CL}"
