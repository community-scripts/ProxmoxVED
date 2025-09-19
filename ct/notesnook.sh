#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/streetwriters/notesnook

APP="notesnook"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-10}"
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
    if [[ ! -d /opt/notesnook ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    msg_info "Stopping Service"
    systemctl stop notesnook
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} (Patience)"
    rm -rf /opt/notesnook
    fetch_and_deploy_gh_release "notesnook" "streetwriters/notesnook" "tarball"
    cd /opt/notesnook
    export NODE_OPTIONS="--max-old-space-size=2560"
    $STD npm install
    $STD npm run build:web
    msg_ok "Updated $APP"

    msg_info "Starting Service"
    systemctl start notesnook
    msg_ok "Started Service"

    msg_ok "Updated Successfully"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
