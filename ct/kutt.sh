#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: tomfrenzel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/thedevs-network/kutt

APP="Kutt"
var_tags="${var_tags:-sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -d $APP_DIR ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    if check_for_gh_release "kutt" "thedevs-network/kutt"; then
        msg_info "Stopping services"
        systemctl stop kutt
        msg_ok "Stopped services"

        msg_info "Updating packages"
        $STD apt-get update
        $STD apt-get dist-upgrade
        msg_ok "Updated packages"

        fetch_and_deploy_gh_release "kutt" "thedevs-network/kutt" "tarball" "latest"

        msg_info "Configuring Kutt"
        cd /opt/kutt
        npm install
        npm run migrate
        msg_ok "Configured Kutt"

        msg_info "Starting services"
        systemctl start kutt
        msg_ok "Started services"
        msg_ok "Updated successfully"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
