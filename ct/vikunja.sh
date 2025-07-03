#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://vikunja.io/

APP="Vikunja"
var_tags="${var_tags:-todo-app}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
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
  if [[ ! -d /opt/vikunja ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Selecting version"
  if whiptail --backtitle "Vikunja Update" --title "🔄 VERSION SELECTION" --yesno \
    "Choose the version type to update to:\n\n• STABLE: Recommended for production use\n• UNSTABLE: Latest development version\n\n⚠️  WARNING: Unstable versions may contain bugs,\nbe incomplete, or cause system instability.\nOnly use for testing purposes.\n\nDo you want to use the UNSTABLE version?\n(No = Stable, Yes = Unstable)" 16 70 --defaultno
  then
    RELEASE="unstable"
    FILENAME="vikunja-${RELEASE}-x86_64.deb"
    msg_ok "Selected UNSTABLE version"
  else
    RELEASE=$(curl -fsSL https://dl.vikunja.io/vikunja/ | grep -oP 'href="/vikunja/\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1)
    FILENAME="vikunja-${RELEASE}-amd64.deb"
    msg_ok "Selected STABLE version: ${RELEASE}"
  fi
  
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop vikunja
    msg_ok "Stopped ${APP}"
    msg_info "Updating ${APP} to ${RELEASE}"
    cd /opt
    rm -rf /opt/vikunja/vikunja
    curl -fsSL "https://dl.vikunja.io/vikunja/$RELEASE/$FILENAME" -o $(basename "https://dl.vikunja.io/vikunja/$RELEASE/$FILENAME")
    export DEBIAN_FRONTEND=noninteractive
    $STD dpkg -i $FILENAME
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated ${APP}"
    msg_info "Starting ${APP}"
    systemctl start vikunja
    msg_ok "Started ${APP}"
    msg_info "Cleaning Up"
    rm -rf /opt/$FILENAME
    msg_ok "Cleaned"
    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3456${CL}"
