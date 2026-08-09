#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: savagecore
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pennydreadful/bookshelf

APP="Bookshelf"
var_tags="${var_tags:-media;eBook}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
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
  if [[ ! -d /opt/bookshelf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  cd /opt/bookshelf-src
  $STD git fetch -q
  RELEASE=$(git log -1 --format=%h origin/develop)
  if [[ ! -f /opt/Bookshelf_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/Bookshelf_version.txt)" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop bookshelf
    msg_ok "Stopped ${APP}"

    create_backup /var/lib/bookshelf

    msg_info "Updating ${APP} to ${RELEASE}"
    git reset --hard origin/develop
    $STD ./build.sh --backend --frontend --packages -f net6.0 -r linux-x64
    rm -rf /opt/bookshelf/bin
    mkdir -p /opt/bookshelf/bin
    $STD cp -r _artifacts/linux-x64/net6.0/Readarr/* /opt/bookshelf/bin/
    chmod +x /opt/bookshelf/bin/Readarr
    rm -rf _output _artifacts _tests
    msg_ok "Updated ${APP} to ${RELEASE}"

    restore_backup

    msg_info "Starting ${APP}"
    systemctl start bookshelf
    msg_ok "Started ${APP}"

    echo "${RELEASE}" >/opt/Bookshelf_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already up to date."
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8787${CL}"
