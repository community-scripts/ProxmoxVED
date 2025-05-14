#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Nícolas Pastorello (opastorello)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/jumpserver/jumpserver

APP="JumpServer"
var_tags="bastion-host;pam"
var_cpu="2"
var_ram="8192"
var_disk="60"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/jumpserver ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/jumpserver/installer/releases/latest | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Updating ${APP} to ${RELEASE}"
    if [[ -d /opt/jumpserver/config ]]; then
      cp -r /opt/jumpserver/config /opt/jumpserver_config_backup
    fi
    echo "${RELEASE}" >/opt/${APP}_version.txt
    rm -rf /opt/jumpserver
    cd /opt
    curl -fsSL "https://github.com/jumpserver/installer/releases/download/${RELEASE}/jumpserver-installer-${RELEASE}.tar.gz" -o jumpserver-installer-${RELEASE}.tar.gz
    mkdir -p /opt/jumpserver
    $STD tar -xzvf jumpserver-installer-${RELEASE}.tar.gz -C /opt/jumpserver --strip-components=1
    if [[ -d /opt/jumpserver_config_backup ]]; then
      cp -r /opt/jumpserver_config_backup /opt/jumpserver/config
      rm -rf /opt/jumpserver_config_backup
    fi
    cd /opt/jumpserver
    yes y | head -n 3 | $STD ./jmsctl.sh upgrade
    $STD ./jmsctl.sh start
    rm -rf /opt/jumpserver-installer-${RELEASE}.tar.gz
    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}."
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
