#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: SunFlowerOwl
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/haugene/docker-transmission-openvpn

APP="transmission-openvpn"
var_tags="${var_tags:-torrent;vpn}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-1}"

header_info "$APP"
variables
color
catch_errors

# this only updates openvpn-transmission, not influxdb or grafana, which are upgraded with apt
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/transmission-openvpn/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn"; then

      fetch_and_deploy_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn" "tarball" "latest" "/opt/docker-transmission-openvpn"

      msg_info "Setup transmission-openvpn"

      msg_ok "Setup transmission-openvpn"
      msg_ok "Updated Successfully"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9091${CL}"
