#!/usr/bin/env bash
# source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
source <(curl -fsSL https://raw.githubusercontent.com/bwhybrow23/ProxmoxVED/refs/heads/opencut/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Ben Whybrow
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/OpenCut-app/OpenCut

APP="opencut"
var_tags="video;editing"
var_cpu="2"
var_ram="2048"
var_disk="10"
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

  # Check if installation is present
  if [[ ! -f /etc/systemd/system/opencut.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Working Directory
  cd /opt/OpenCut

  # Check for updates
  msg_info "Checking for updates to ${APP}..."

  LOCAL_COMMIT=$(git rev-parse HEAD)
  REMOTE_COMMIT=$(git ls-remote origin HEAD | awk '{print $1}')

  if [[ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]]; then
    msg_info "Updating ${APP} to the latest version..."

    msg_info "Stopping services"
    systemctl stop opencut.service
    docker compose down
    msg_ok "Stopped services"

    msg_info "Pulling latest changes from the repository"
    git pull --rebase
    msg_ok "Pulled latest changes"

    msg_info "Installing dependencies"
    bun install
    msg_ok "Installed dependencies"

    msg_info "Starting backend services"
    docker compose up -d
    msg_ok "Started backend services"

    msg_info "Starting OpenCut service"
    systemctl daemon-reload
    systemctl start opencut.service
    msg_ok "Started OpenCut service"

    msg_ok "Updated ${APP} to the latest version!"
  else
    msg_ok "${APP} is already up to date."
  fi

}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
