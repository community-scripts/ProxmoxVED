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

  # Check if installation is present | -f for file, -d for folder
  if [[ ! -d "/opt/${APP}" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  RELEASE=$(curl -fsSL https://api.github.com/repos/HydroshieldMKII/Guardian/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    # Stopping Services
    msg_info "Stopping $APP"
    systemctl stop guardian-backend guardian-frontend
    msg_ok "Stopped $APP"

    # Creating Backup
    msg_info "Creating Backup"
    tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /opt/Guardian
    msg_ok "Backup Created"

    # Execute Update
    msg_info "Updating $APP to v${RELEASE}"
    cd /tmp
    curl -fsSL -o "${RELEASE}.zip" "https://github.com/HydroshieldMKII/Guardian/archive/refs/tags/${RELEASE}.zip"
    unzip -q "${RELEASE}.zip"
    rm -rf /opt/Guardian
    mv "Guardian-${RELEASE}/" "/opt/Guardian"
    
    # Build Backend
    cd /opt/Guardian/backend
    npm ci
    npm run build
    
    # Build Frontend
    cd /opt/Guardian/frontend
    npm ci
    npm run build
    
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated $APP to v${RELEASE}"

    # Starting Services
    msg_info "Starting $APP"
    systemctl start guardian-backend guardian-frontend
    msg_ok "Started $APP"

    # Cleaning up
    msg_info "Cleaning Up"
    rm -rf /tmp/"${RELEASE}.zip" /tmp/"Guardian-${RELEASE}"
    msg_ok "Cleanup Completed"

    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
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
