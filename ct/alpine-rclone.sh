#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rclone/rclone

APP="Alpine-rclone"
var_tags="${var_tags:-alpine;backup}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-0.2}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.21}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  RELEASE=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ] || [ ! -f /opt/${APP}_version.txt ]; then
    msg_info "Updating ${APP} LXC"
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/rclone/rclone/releases/download/v${RELEASE}/rclone-v${RELEASE}-linux-amd64.zip" -o $temp_file
    $STD unzip -j -o $temp_file '*/**' -d /opt/rclone
    rm -f $temp_file
    echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi

  exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following IP:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
