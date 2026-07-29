#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: N0t4R0b0t
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/tenox7/wrp

APP="WRP"
var_tags="${var_tags:-proxy;network;browser}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/wrp/wrp ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "wrp" "tenox7/wrp"; then
    msg_info "Stopping Service"
    systemctl stop wrp
    msg_ok "Stopped Service"

    local wrp_asset
    case "$(dpkg --print-architecture)" in
      amd64) wrp_asset="wrp-amd64-linux" ;;
      arm64) wrp_asset="wrp-arm64-linux" ;;
      armhf) wrp_asset="wrp-arm-linux" ;;
      *) msg_error "Unsupported architecture: $(dpkg --print-architecture)"; exit ;;
    esac
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wrp" "tenox7/wrp" "singlefile" "latest" "/opt/wrp" "$wrp_asset"

    msg_info "Starting Service"
    systemctl start wrp
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
echo -e "${INFO}${YW}Point a legacy browser at:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
