#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: tremor021 (Slaviša Arežina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://teamspeak.com/en/

APP="Alpine-TeamSpeak-Server"
var_tags="${var_tags:-alpine;communication}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.22}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info

  if [[ ! -d /opt/teamspeak-server ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  # define custom command to scrape version
  local CUSTOM_CMD="curl -fsSL https://teamspeak.com/en/downloads/#server \
    | sed -n '/teamspeak3-server_linux_amd64-/ { s/.*teamspeak3-server_linux_amd64-\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p; q }'"

  if check_for_update "${APP}" "${CUSTOM_CMD}"; then
    local release="$CHECK_UPDATE_RELEASE"

    msg_info "Updating ${APP} LXC to v${release}"
    $STD apk -U upgrade
    $STD service teamspeak stop

    curl -fsSL "https://files.teamspeak-services.com/releases/server/${release}/teamspeak3-server_linux_amd64-${release}.tar.bz2" -o ts3server.tar.bz2
    tar -xf ts3server.tar.bz2
    cp -ru teamspeak3-server_linux_amd64/* /opt/teamspeak-server/

    rm -f ts3server.tar.bz2
    rm -rf teamspeak3-server_linux_amd64

    echo "${release}" >~/.teamspeak-server

    $STD service teamspeak start
    msg_ok "Updated ${APP} successfully to v${release}"
  fi

  exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following IP:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:9987${CL}"
