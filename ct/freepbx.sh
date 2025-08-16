#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/vsc55/community-scripts-ProxmoxVED/refs/heads/freepbx/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Arian Nasr (arian-nasr)
# Updated by: Javier Pastor (vsc55)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.freepbx.org/

APP="FreePBX"
var_tags="pbx;voip;telephony"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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

  if [[ ! -f /lib/systemd/system/freepbx.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating $APP LXC"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated $APP LXC"

  msg_info "Updating $APP Modules"
  $STD fwconsole ma updateall
  $STD fwconsole reload
  msg_ok "Updated $APP Modules"

  exit
}

start

if whiptail --title "Commercial Modules" --yesno "Remove Commercial modules?" --defaultno 10 50; then
  export ONLY_OPENSOURCE="yes"

  if whiptail --title "Firewall Module" --yesno "Do you want to KEEP the Firewall module (and sysadmin)?" 10 50; then
    export REMOVE_FIREWALL="no"
  else
    export REMOVE_FIREWALL="yes"
  fi
else
  export ONLY_OPENSOURCE="no"
  export REMOVE_FIREWALL="no"
fi

build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
