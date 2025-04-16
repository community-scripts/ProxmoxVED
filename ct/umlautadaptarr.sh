#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: elvito
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/PCJones/UmlautAdaptarr

APP="Umlautadaptarr"
var_tags="arr"
var_cpu="1"
var_ram="512"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /opt/UmlautAdaptarr/appsettings.json ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating $APP..."
    $STD systemctl stop umlautadaptarr
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT
    RELEASE=$(curl -s https://api.github.com/repos/PCJones/Umlautadaptarr/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
    curl -fsSL "https://github.com/PCJones/Umlautadaptarr/releases/download/${RELEASE}/linux-x64.zip" -o $temp_file
    $STD unzip -u $temp_file '*/**' -d /opt/UmlautAdaptarr
    systemctl start umlautadaptarr
    msg_ok "$APP has been updated."
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5005${CL}"
