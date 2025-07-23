#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Cleanuparr/Cleanuparr

APP="Cleanuparr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
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
    if [[ ! -f /opt/cleanuparr/Cleanuparr ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Stopping ${APP}"
    systemctl stop cleanuparr
    msg_ok "Stopped ${APP}"

    msg_info "Updating ${APP}"
    cd /opt/cleanuparr
    RELEASE=$(curl -fsSL https://api.github.com/repos/Cleanuparr/Cleanuparr/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
    curl -fsSLO "https://github.com/Cleanuparr/Cleanuparr/releases/download/v${RELEASE}/Cleanuparr-${RELEASE}-linux-amd64.zip"
    unzip -oq "Cleanuparr-${RELEASE}-linux-amd64.zip"
    rm -f "Cleanuparr-${RELEASE}-linux-amd64.zip"
    chmod +x /opt/cleanuparr/Cleanuparr
    msg_ok "Updated ${APP}"

    msg_info "Starting ${APP}"
    systemctl start cleanuparr
    msg_ok "Started ${APP}"
    msg_ok "Updated Successfully"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:11011${CL}"