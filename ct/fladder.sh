#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/wendyliga/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: wendyliga
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/DonutWare/Fladder

APP="Fladder"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/fladder ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  # Get latest version from GitHub
  RELEASE=$(curl -fsSL https://api.github.com/repos/DonutWare/Fladder/releases/latest | \
    grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
  if [[ -z "$RELEASE" ]]; then
    msg_error "Failed to fetch latest release version from GitHub"
    exit 1
  fi
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Service"
    systemctl stop nginx
    msg_ok "Stopped Service"

    msg_info "Backing up configuration"
    if [[ -f /opt/fladder/assets/config/config.json ]]; then
      cp /opt/fladder/assets/config/config.json /tmp/fladder_config.json.bak
      msg_ok "Configuration backed up"
    elif [[ -f /opt/fladder/data/flutter_assets/config/config.json ]]; then
      cp /opt/fladder/data/flutter_assets/config/config.json /tmp/fladder_config.json.bak
      msg_ok "Configuration backed up"
    fi

    msg_info "Updating ${APP} to ${RELEASE}"
    cd /opt
    wget -q "https://github.com/DonutWare/Fladder/releases/download/${RELEASE}/Fladder-Web-${RELEASE#v}.zip"
    rm -rf /opt/fladder
    unzip -q "Fladder-Web-${RELEASE#v}.zip" -d fladder
    rm -f "Fladder-Web-${RELEASE#v}.zip"
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated ${APP} to ${RELEASE}"

    msg_info "Restoring configuration"
    if [[ -f /tmp/fladder_config.json.bak ]]; then
      mkdir -p /opt/fladder/assets/config
      cp /tmp/fladder_config.json.bak /opt/fladder/assets/config/config.json
      rm -f /tmp/fladder_config.json.bak
      msg_ok "Configuration restored"
    fi

    msg_info "Starting Service"
    systemctl start nginx
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
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
echo -e "${INFO}${YW} Access it using the following IP:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
