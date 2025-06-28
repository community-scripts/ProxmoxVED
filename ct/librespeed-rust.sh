#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Joseph Stubberfield (stubbers)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/librespeed/speedtest-rust

APP="Librespeed Rust"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
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
  if [[ ! -d /var/lib/librespeed-rs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/librespeed/speedtest-rust/releases/latest | grep '"tag_name"' | sed -E 's/.*"tag_name": "v([^"]+).*/\1/')
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Services"
    systemctl stop librespeed-rs
    msg_ok "Services Stopped"

    msg_info "Updating ${APP} to v${RELEASE}"
    $STD apt-get update
    $STD apt-get -y upgrade
    mv /var/lib/librespeed /var/lib/librespeed-backup
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/librespeed/speedtest-rust/releases/download/v${RELEASE}/librespeed-rs-x86_64-unknown-linux-gnu.deb" -o "$temp_file"
    $STD dpkg -u "$temp_file"
    rm -rf "$temp_file"
    rm -rf /var/lib/librespeed-backup
    echo "${RELEASE}" >/opt/"${APPLICATION}"_version.txt
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start librespeed-rs
    msg_ok "Started Service"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
