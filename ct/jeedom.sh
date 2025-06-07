#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Mips2648
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://jeedom.com/

APP="Jeedom"
var_tags="automation;smarthome"
var_cpu="2"
var_ram="2048"
var_disk="16"
var_os="debian"
var_version="11"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if ! lsb_release -d | grep -q "Debian GNU/Linux"; then
        msg_error "Wrong OS detected. Jeedom only supports Debian"
        exit 1
    fi

    if [[ ! -f /var/www/html/core/config/version ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    msg_info "Updating OS"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "OS updated, you can now update Jeedom from the Web UI."
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
