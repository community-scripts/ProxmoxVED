#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: b3nw
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vrtmrz/obsidian-livesync

# App Default Values
APP="Obsidian-LiveSync"
# Max 2 tags, semicolon-separated
var_tags="${var_tags:-database;sync}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  version_file="/opt/${APP}_version.txt"
  if [[ ! -f "${version_file}" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating OS packages"
  $STD apt-get update
  $STD apt-get -o Dpkg::Options::="--force-confold" -y dist-upgrade
  msg_ok "Updated OS packages"

  if command -v couchdb &>/dev/null; then
    COUCH_VER=$(couchdb -V 2>/dev/null | awk '{print $3}')
    [[ -z "${COUCH_VER}" ]] && COUCH_VER=$(dpkg -s couchdb 2>/dev/null | awk -F': ' '/^Version:/{print $2}')
    [[ -n "${COUCH_VER}" ]] && echo "${COUCH_VER}" >"${version_file}"
    systemctl restart couchdb || true
    msg_ok "CouchDB service restarted"
  fi
  msg_ok "Update completed"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5984/_utils/${CL}"
