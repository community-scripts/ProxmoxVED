#!/usr/bin/env bash
source <(curl -s https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/community-scripts/ProxmoxVE

APP="Docspell"
var_tags="${var_tags:-document}"
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
    if [[ ! -d /opt/docspell ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating ${APP} LXC"
    cd /opt/bookstack
    git config --global --add safe.directory /opt/bookstack >/dev/null 2>&1
    git pull origin release >/dev/null 2>&1
    composer install --no-interaction --no-dev >/dev/null 2>&1
    php artisan migrate --force >/dev/null 2>&1
    php artisan cache:clear
    php artisan config:clear
    php artisan view:clear
    msg_ok "Updated Successfully"
    exit
    msg_error "There is currently no update path available."
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7880${CL}"
