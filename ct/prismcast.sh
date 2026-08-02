#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: subsistence
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/hjdhjd/prismcast

APP="PrismCast"
var_tags="${var_tags:-media;streaming;plex;hdhomerun}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/prismcast ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "prismcast" "hjdhjd/prismcast"; then
    msg_info "Stopping Service"
    systemctl stop prismcast
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "prismcast" "hjdhjd/prismcast" "tarball"

    msg_info "Building PrismCast"
    cd /opt/prismcast
    export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
    $STD npm ci
    $STD npm run build
    msg_ok "Built PrismCast"

    msg_info "Starting Service"
    systemctl start prismcast
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}PrismCast tuner (add manually in Plex as ${IP}:5004):${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:5004/discover.json${CL}"
echo -e "${INFO}${YW}PrismCast web interface:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:5589${CL}"
echo -e "${INFO}${YW}Chrome direct VNC:${CL}"
echo -e "${GATEWAY}${BGN}vnc://${IP}:5900${CL}"
echo -e "${INFO}${YW}Chrome noVNC (recommended):${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:6080/vnc.html${CL}"
