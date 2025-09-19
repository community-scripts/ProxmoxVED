#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source:

APP="Squirrel Servers Manager"
var_tags="${var_tags:-manager}"
var_disk="${var_disk:-10}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.21}"
var_unprivileged="${var_unprivileged:-1}"

variables
color
catch_errors

function update_script() {
    header_info
    if [[ ! -d /opt/squirrelserversmanager ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating ${APP}"
    pm2 stop "squirrelserversmanager-frontend"
    pm2 stop "squirrelserversmanager-backend"
    cd /opt/squirrelserversmanager
    git pull
    cd /opt/squirrelserversmanager/shared-lib
    npm ci &>/dev/null
    npm run build
    cd /opt/squirrelserversmanager/server
    npm ci &>/dev/null
    npm run build
    cd /opt/squirrelserversmanager/client
    npm ci &>/dev/null
    npm run build
    pm2 flush
    pm2 restart "squirrelserversmanager-frontend"
    pm2 restart "squirrelserversmanager-backend"
    msg_ok "Successfully Updated ${APP}"
    exit
}

start
build_container
description
msg_info "Setting Container to Normal Resources"
pct set $CTID -memory 1024
pct set $CTID -cores 1
msg_ok "Set Container to Normal Resources"
msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}:80${CL} \n"
