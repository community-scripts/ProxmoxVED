#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: SimplyMinimal
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/tailscale/golink

APP="Golink"
var_tags="${var_tags:-shortlink;tailscale}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
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

  if [[ ! -d /opt/golink ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for updates"
  cd /opt/golink || exit
  $STD git fetch origin
  CURRENT_COMMIT=$(git rev-parse HEAD)
  LATEST_COMMIT=$(git rev-parse origin/main)

  if [[ "$CURRENT_COMMIT" != "$LATEST_COMMIT" ]]; then
    msg_info "Stopping $APP"
    systemctl stop golink
    msg_ok "Stopped $APP"

    msg_info "Updating $APP"
    $STD git reset --hard origin/main
    $STD go mod tidy
    $STD go build -o golink ./cmd/golink
    chmod +x golink
    RELEASE=$(git describe --tags --always 2>/dev/null || echo "main-$(git rev-parse --short HEAD)")
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated $APP to ${RELEASE}"

    msg_info "Starting $APP"
    systemctl start golink
    msg_ok "Started $APP"
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already up to date"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Configuration details saved to ~/golink.creds${CL}"
echo -e "${INFO}${YW} Default access (development mode):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} For Tailscale access: Configure TS_AUTHKEY in /opt/golink/.env${CL}"
