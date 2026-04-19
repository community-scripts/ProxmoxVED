#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: John McLear (JohnMcLear)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://etherpad.org

APP="Etherpad"
var_tags="${var_tags:-docs;collaboration;editor}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/etherpad-lite ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "etherpad-lite" "ether/etherpad-lite"; then
    msg_info "Stopping Service"
    systemctl stop etherpad
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    [ -f /opt/etherpad-lite/settings.json ] && cp /opt/etherpad-lite/settings.json /opt/etherpad-settings.json.bak
    [ -d /opt/etherpad-lite/var ] && cp -a /opt/etherpad-lite/var /opt/etherpad-var.bak
    msg_ok "Backed up Configuration"

    LATEST_TAG=$(curl -fsSL https://api.github.com/repos/ether/etherpad-lite/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
    msg_info "Updating to ${LATEST_TAG}"
    cd /opt/etherpad-lite
    $STD git fetch --tags --prune
    $STD git checkout "${LATEST_TAG}"
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    $STD corepack enable
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build:etherpad
    msg_ok "Updated to ${LATEST_TAG}"

    msg_info "Restoring Configuration"
    [ -f /opt/etherpad-settings.json.bak ] && mv /opt/etherpad-settings.json.bak /opt/etherpad-lite/settings.json
    [ -d /opt/etherpad-var.bak ] && rm -rf /opt/etherpad-lite/var && mv /opt/etherpad-var.bak /opt/etherpad-lite/var
    chown -R etherpad:etherpad /opt/etherpad-lite
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start etherpad
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9001${CL}"
