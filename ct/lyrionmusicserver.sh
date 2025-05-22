#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://lyrion.org/getting-started/

APP="Lyrion Music Server"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-60}"
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
    if [[ ! -d /var ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating $APP LXC"
    $STD apt-get update
    $STD apt-get -y upgrade

    DEB_URL=$(curl -s 'https://lyrion.org/getting-started/' | grep -oP '<a\s[^>]*href="\K[^"]*amd64\.deb(?="[^>]*>)' | head -n 1)
    LYRION_VERSION=$(echo "$DEB_URL" | grep -oP 'lyrionmusicserver_\K[0-9.]+(?=_amd64\.deb)')
    DEB_FILE="/tmp/lyrionmusicserver_${LYRION_VERSION}_amd64.deb"
    curl -fsSL -o "$DEB_FILE" "$DEB_URL"
    $STD apt install "$DEB_FILE" -y

    msg_ok "Updated $APP LXC"

    msg_info "Cleaning up"
    $STD rm -f "$DEB_FILE"
    $STD apt-get -y autoremove
    $STD apt-get -y autoclean
    msg_ok "Cleaned"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the web interface at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"
echo -e "${INFO}${YW} Check logs for setup details: ~/lyrion-install.log${CL}"
