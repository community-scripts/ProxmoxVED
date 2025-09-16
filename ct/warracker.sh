#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/bvdberg01/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: BvdBerg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/sassanix/Warracker/

APP="warracker"
var_tags="${var_tags:-warranty}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
init_error_traps

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/signoz ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    if check_for_gh_release "signoz" "SigNoz/signoz"; then
        msg_info "Stopping Services"
        systemctl stop warracker
        systemctl stop ngninx
        msg_ok "Stopped Services"

        fetch_and_deploy_gh_release "warracker" "sassanix/Warracker" "tarball" "latest" "/opt/warracker"

        msg_info "Updating ${APP}"

        msg_ok "Updated $APP"

        msg_info "Starting Services"
        systemctl start warracker
        systemctl start ngninx
        msg_ok "Started Services"

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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
