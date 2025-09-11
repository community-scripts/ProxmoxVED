#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 communtiy-scripts ORG
# Author: Giovanni `evilaliv3` Pellerano
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/globaleaks/globaleaks-whistleblowing-software
## App Default Values
APP="GlobaLeaks"
var_tags="${var_tags:-whistleblowing-software}"
var_disk="${var_disk:-4}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -f /usr/sbin/globaleaks ]]; then
        msg_error "No ${APP} installation found!"
        exit
    fi

    msg_info "Updating $APP LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    $STD bash <(curl -fsSL https://deb.globaleaks.org//install.sh) -y

    $STD sh -c 'echo "deb [signed-by=/etc/apt/trusted.gpg.d/globaleaks.gpg] http://deb.globaleaks.org $(lsb_release -sc) main" > /etc/apt/sources.list.d/globaleaks.list'
    $STD apt-get update
    $STD apt-get -y install globaleaks

    msg_ok "Updated $APP LXC"
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN} ${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
