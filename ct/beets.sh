#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: JaredVititoe
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://beets.io/

# App Default Values
APP="Beets"
var_tags="media;music"
var_cpu="2"
var_ram="1024"
var_disk="8"
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

    if [[ ! -d /opt/beets ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    msg_info "Updating ${APP}"
    source /opt/beets/venv/bin/activate
    $STD pip install --upgrade beets pyacoustid pylast requests beautifulsoup4 flask
    deactivate
    msg_ok "Updated ${APP}"

    msg_info "Updating System Packages"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated System Packages"

    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Beets is a CLI tool. Access the container via:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct enter <CTID>${CL}"
echo -e "${INFO}${YW} Run 'beet' to use Beets. Config at /opt/beets/config.yaml${CL}"
echo -e "${INFO}${YW} If web plugin enabled, access at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8337${CL}"
