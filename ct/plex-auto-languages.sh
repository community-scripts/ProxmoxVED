#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Shaalan
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RemiRigal/Plex-Auto-Languages

# Import main orchestrator
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Application Configuration
APP="Plex-Auto-Languages"
var_tags="${var_tags:-plex;media;automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# Display header
header_info "$APP"

# Initialize
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/plex-auto-languages ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping ${APP} Service"
  systemctl stop plex-auto-languages
  msg_ok "Stopped ${APP} Service"

  msg_info "Updating ${APP}"
  cd /opt/plex-auto-languages || exit
  $STD git pull
  $STD /opt/plex-auto-languages/venv/bin/pip install -r requirements.txt
  msg_ok "Updated ${APP}"

  msg_info "Starting ${APP} Service"
  systemctl start plex-auto-languages
  msg_ok "Started ${APP} Service"

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the configuration file:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/plex-auto-languages/config/config.yaml${CL}"
echo -e "${INFO}${YW} You must edit the config to set your Plex URL and Token before the service will work.${CL}"
