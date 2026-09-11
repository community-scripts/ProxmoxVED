#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Borja Garduño (Borja-Garduno)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://airdcpp.net/

APP="AirDCPP"
var_tags="${var_tags:-downloader;p2p;files}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # official portable ARM is armhf, not aarch64
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/airdcpp/airdcppd ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "airdcpp" "airdcpp-web/airdcpp-webclient"; then
    ASSET_URL=$(curl -fsSL https://airdcpp.net/docs/installation/linux-binaries.html |
      grep -oE 'https://web-builds\.airdcpp\.net/stable/airdcpp_[^"]+_64-bit_portable\.tar\.gz' |
      head -1)
    if [[ -z "${ASSET_URL}" ]]; then
      msg_error "Could not resolve the official 64-bit portable download URL."
      exit 1
    fi

    msg_info "Stopping Service"
    systemctl stop airdcpp
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_from_url "${ASSET_URL}" /opt/airdcpp
    chmod +x /opt/airdcpp/airdcppd
    echo "${CHECK_UPDATE_RELEASE#v}" >~/.airdcpp

    msg_info "Starting Service"
    systemctl start airdcpp
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
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:5600${CL}"
