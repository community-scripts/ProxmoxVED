#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: cobalt (cobaltgit)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/matze/wastebin

APP="Alpine-Wastebin"
var_tags="${var_tags:-file;code}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.22}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/wastebin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if ! command -v zstd >/dev/null 2>&1; then
    $STD apk add --no-cache zstd
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/matze/wastebin/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ ! -f "~/.wastebin" ]] || [[ "${RELEASE}" != "$(cat "~/.wastebin")" ]]; then
    msg_info "Stopping Wastebin"
    rc-service wastebin stop
    msg_ok "Wastebin Stopped"

    msg_info "Updating Wastebin"
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/matze/wastebin/releases/download/${RELEASE}/wastebin_${RELEASE}_x86_64-unknown-linux-musl.tar.zst" -o "$temp_file"
    zstd -dc $temp_file | tar x -C /opt/wastebin wastebin wastebin-ctl
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated Wastebin"

    msg_info "Starting Wastebin"
    rc-service wastebin start
    msg_ok "Started Wastebin"

    msg_info "Cleaning Up"
    rm -f $temp_file
    msg_ok "Cleanup Completed"
    msg_ok "Updated Successfully"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8088${CL}"

