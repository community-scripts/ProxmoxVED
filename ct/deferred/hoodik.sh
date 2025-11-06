#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source:

APP="Hoodik"
# shellcheck disable=SC2034
var_tags="${var_tags:-sharing}"
var_disk="${var_disk:-7}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
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
    if [[ ! -d /opt/hoodik ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    RELEASE=$(curl -fsSL https://api.github.com/repos/hudikhq/hoodik/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        msg_info "Stopping Services"
        systemctl stop hoodik
        msg_ok "Services Stopped"

        msg_info "Updating ${APP} to ${RELEASE}"
        cd /opt
        if [ -d hoodik_bak ]; then
            rm -rf hoodik_bak
        fi
        mv hoodik hoodik_bak
        curl -fsSL "https://github.com/hudikhq/hoodik/archive/refs/tags/${RELEASE}.zip"
        unzip -q ${RELEASE}.zip
        mv hoodik-${RELEASE} /opt/hoodik
        cd /opt/hoodik
        cargo update -q
        cargo build -q --release
        msg_ok "Updated Hoodik"

        msg_info "Starting Services"
        systemctl start hoodik
        msg_ok "Started Services"

        msg_info "Cleaning Up"
        rm -R /opt/${RELEASE}.zip
        rm -R /opt/hoodik_bak
        msg_ok "Cleaned"
        msg_ok "Updated Successfully"
    else
        msg_ok "No update required. ${APP} is already at ${RELEASE}"
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
