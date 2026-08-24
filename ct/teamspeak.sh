#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nicolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.teamspeak.com/

APP="TeamSpeak"
var_tags="${var_tags:-voice;chat;communication}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-no}" # TeamSpeak publishes no arm64 Linux binary

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/teamspeak ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  TS_URL=$(curl -fsSL "https://www.teamspeak.com/en/downloads/" | grep -oE 'https://[^"]*teamspeak3-server_linux_amd64-[0-9.]+\.tar\.bz2' | head -1)
  TS_VERSION=$(echo "$TS_URL" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if [[ "$TS_VERSION" == "$(cat ~/.teamspeak 2>/dev/null)" ]]; then
    msg_ok "No update required. ${APP} is already at v${TS_VERSION}"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop teamspeak
  msg_ok "Stopped Service"

  curl -fsSL "$TS_URL" | tar -xjf - -C /opt/teamspeak --strip-components=1
  echo "${TS_VERSION}" >~/.teamspeak

  msg_info "Starting Service"
  systemctl start teamspeak
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Voice port (UDP): ${CL}${BGN}${IP}:9987${CL}"
echo -e "${INFO}${YW}ServerAdmin privilege key saved to ~/teamspeak.creds${CL}"
