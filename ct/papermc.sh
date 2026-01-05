#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Dmytro (vorotech)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/PaperMC/Paper

APP="PaperMC"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-16}"
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

  if [[ ! -d /opt/minecraft ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PAPER_API_ROOT="https://api.papermc.io/v2/projects/paper"
  LATEST_VERSION=$(curl -fsSL "${PAPER_API_ROOT}" | jq -r '.versions | last')
  LATEST_BUILD=$(curl -fsSL "${PAPER_API_ROOT}/versions/${LATEST_VERSION}" | jq -r '.builds | last')
  BUILD_JSON=$(curl -fsSL "${PAPER_API_ROOT}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}")
  EXPECTED_SHA=$(printf '%s' "$BUILD_JSON" | jq -r '.downloads.application.sha256')
  JAR_NAME=$(printf '%s' "$BUILD_JSON" | jq -r '.downloads.application.name')
  DOWNLOAD_URL="${PAPER_API_ROOT}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}/downloads/${JAR_NAME}"

  msg_info "Stopping Services"
  systemctl stop mc-backup.timer
  systemctl stop minecraft
  msg_ok "Stopped Services"

  msg_info "Updating $APP to v${LATEST_VERSION}-${LATEST_BUILD}"
  cp -r /opt/minecraft/ /opt/minecraft-backup
  download_with_progress ${DOWNLOAD_URL} /opt/minecraft/server.jar
  
  cd /opt/minecraft
  ACTUAL_SHA=$(sha256sum server.jar | awk '{print $1}')
  if [[ -n "$EXPECTED_SHA" && "$EXPECTED_SHA" != "null" ]]; then
    if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
      msg_error "SHA256 mismatch for PaperMC (expected ${EXPECTED_SHA}, got ${ACTUAL_SHA})"
      exit 1
    fi
    msg_ok "SHA256 verified: ${ACTUAL_SHA}"
  else
    msg_warn "No upstream SHA provided; computed: ${ACTUAL_SHA}"
  fi
 
  chown -R minecraft:minecraft /opt/minecraft
  
  msg_info "Starting Services"
  systemctl start mc-backup.timer
  systemctl start minecraft
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7867${CL}"
