#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://gitea.io

APP="Alpine-Gitea"
var_tags="${var_tags:-alpine;git}"
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
    msg_info "Updating Alpine Packages"
    $STD apk update
    $STD apk upgrade
    msg_ok "Updated Alpine Packages"

    msg_info "Updating Gitea"
    $STD apk upgrade gitea
    msg_ok "Updated Gitea"

    msg_info "Restarting Gitea"
    $STD rc-service gitea restart
    msg_ok "Restarted Gitea"

    exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
