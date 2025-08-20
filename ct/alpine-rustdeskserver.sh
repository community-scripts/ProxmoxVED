#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rustdesk/rustdesk-server

APP="Alpine-RustDeskServer"
var_tags="${var_tags:-alpine;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
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

  if [[ ! -d /opt/rustdesk-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi
  RELEASE=$(curl -s https://api.github.com/repos/TwiN/RustDesk Server/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [ "${RELEASE}" != "$(cat /opt/RustDesk Server_version.txt)" ] || [ ! -f /opt/RustDesk Server_version.txt ]; then
    msg_info "Updating ${APP} LXC"
    $STD apk -U upgrade
    $STD service RustDesk Server stop
    mv /opt/RustDesk Server/config/config.yaml /opt
    rm -rf /opt/RustDesk Server/*
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/TwiN/RustDesk Server/archive/refs/tags/v${RELEASE}.tar.gz" -o "$temp_file"
    tar zxf "$temp_file" --strip-components=1 -C /opt/RustDesk Server
    cd /opt/RustDesk Server
    $STD go mod tidy
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o RustDesk Server .
    setcap CAP_NET_RAW+ep RustDesk Server
    mv /opt/config.yaml config
    rm -f "$temp_file"
    echo "${RELEASE}" >/opt/RustDesk Server_version.txt
    $STD service RustDesk Server start
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
