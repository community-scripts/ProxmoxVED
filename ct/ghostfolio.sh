#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: lucasfell
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ghostfol.io/

APP="Ghostfolio"
var_tags="${var_tags:-finance;investment}"
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

  if [[ ! -f /opt/ghostfolio/dist/apps/api/main.js ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping $APP"
  systemctl stop ghostfolio
  msg_ok "Stopped $APP"

  msg_info "Creating Backup"
  tar -czf "/opt/ghostfolio_backup_$(date +%F).tar.gz" /opt/ghostfolio
  msg_ok "Backup Created"

  msg_info "Updating $APP"
  cd /opt/ghostfolio
  git fetch --all
  RELEASE=$(git describe --tags --abbrev=0 origin/main)
  if [[ "${RELEASE}" != "$(cat /opt/ghostfolio_version.txt)" ]] || [[ ! -f /opt/ghostfolio_version.txt ]]; then
    git checkout ${RELEASE}
    npm ci
    npm run build:production
    npm run database:migrate
    echo "${RELEASE}" >/opt/ghostfolio_version.txt
    msg_ok "Updated $APP to ${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi

  msg_info "Starting $APP"
  systemctl start ghostfolio
  msg_ok "Started $APP"

  msg_info "Cleaning Up"
  npm cache clean --force
  msg_ok "Cleanup Completed"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3333${CL}"
