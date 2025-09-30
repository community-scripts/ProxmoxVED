#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/HydroshieldMKII/ProxmoxVED/refs/heads/add-guardian-app/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: HydroshieldMKII
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/HydroshieldMKII/Guardian

APP="Guardian"
var_tags="${var_tags:-media;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
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

  if [[ ! -d "/opt/${APP}" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi


  RELEASE=$(curl -fsSL https://api.github.com/repos/HydroshieldMKII/Guardian/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then

    msg_info "Stopping $APP"
    cd /opt/Guardian
    docker compose down
    msg_ok "Stopped $APP"

    msg_info "Updating $APP to v${RELEASE}"
    # Download new docker-compose.yml
    curl -fsSL -o docker-compose.yml "https://raw.githubusercontent.com/HydroshieldMKII/Guardian/main/docker-compose.yml"

    # Pull new Docker images
    docker compose pull

    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    cd /opt/Guardian
    docker compose up -d
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -f /tmp/plex-guard.db.backup
    docker system prune -f
    msg_ok "Cleanup Completed"

    msg_ok "Update Successful"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
