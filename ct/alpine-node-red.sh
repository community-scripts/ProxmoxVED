#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://redis.io/

APP="Alpine-Node-Red"
var_tags="${var_tags:-alpine;automation}"
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
    msg_info "Updating Alpine Packages"
    apk update && apk upgrade
    msg_ok "Updated Alpine Packages"

    msg_info "Updating Node.js and npm"
    apk upgrade nodejs npm
    msg_ok "Updated Node.js and npm"

    msg_info "Updating Node-RED"
    npm install -g --unsafe-perm node-red
    msg_ok "Updated Node-RED"

    msg_info "Restarting Node-RED"
    rc-service nodered restart
    msg_ok "Restarted Node-RED"
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable on port 1880.
         ${BL}http://<your-ip>:1880${CL} \n"
