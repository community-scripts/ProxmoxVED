#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/fstof/ProxmoxVED/refs/heads/donetick/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: fstof
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/donetick/donetick

# App Default Values
APP="Donetick"
var_tags="${var_tags:-productivity;tasks}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  # Check if installation is present | -f for file, -d for folder
  if [[ ! -f /opt/donetick ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  RELEASE=$(curl -fsSL https://api.github.com/repos/donetick/donetick/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/donetick/donetick_version.txt)" ]] || [[ ! -f /opt/donetick/donetick_version.txt ]]; then
    # Stopping Services
    msg_info "Stopping $APP"
    systemctl stop donetick
    msg_ok "Stopped $APP"

    # Execute Update
    msg_info "Updating $APP to ${RELEASE}"
    curl -fsSL "https://github.com/donetick/donetick/releases/download/${RELEASE}/donetick_Linux_x86_64.tar.gz" | tar -xz -C .
    mv donetick "/opt/donetick/donetick"
    msg_ok "Updated $APP to ${RELEASE}"

    # Starting Services
    msg_info "Starting $APP"
    systemctl start donetick
    msg_ok "Started $APP"

    # Cleaning up
    msg_info "Cleaning Up"
    rm -rf config
    msg_ok "Cleanup Completed"

    # Last Action
    echo "${RELEASE}" > /opt/donetick/donetick_version.txt
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2021${CL}"
