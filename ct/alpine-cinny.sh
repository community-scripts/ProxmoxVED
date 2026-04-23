#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tobias Salzmann (Eun)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/cinnyapp/cinny

APP="Alpine-Cinny"
var_tags="${var_tags:-alpine;matrix}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.21}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info

  if [ ! -d /usr/share/nginx/html ]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/cinnyapp/cinny/releases/latest | grep '"tag_name":' | cut -d '"' -f4)
  if [ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ] || [ ! -f /opt/${APP}_version.txt ]; then
    msg_info "Updating ${APP} LXC"
    $STD apk -U upgrade
    temp_file=$(mktemp)
    curl -fsSL "https://github.com/cinnyapp/cinny/releases/download/${RELEASE}/cinny-${RELEASE}.tar.gz" -o "$temp_file"
    cp /usr/share/nginx/html/config.json /tmp/cinny_config.json
    rm -rf /usr/share/nginx/html/*
    tar -xzf "$temp_file" --strip-components=1 -C /usr/share/nginx/html
    cp /tmp/cinny_config.json /usr/share/nginx/html/config.json
    rm -f /tmp/cinny_config.json "$temp_file"
    echo "${RELEASE}" >/opt/${APP}_version.txt
    $STD rc-service nginx restart
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit 0
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following IP:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
