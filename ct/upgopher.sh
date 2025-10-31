#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Eduard González (wanetty)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/wanetty/upgopher

APP="Upgopher"
var_tags="${var_tags:-file-sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
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
    if [[ ! -d /opt/upgopher ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    if check_for_gh_release "upgopher" "wanetty/upgopher"; then
        msg_info "Stopping Services"
        systemctl stop upgopher
        msg_ok "Stopped Services"

        cd /opt/upgopher
        RELEASE_URL=$(curl -s https://api.github.com/repos/wanetty/upgopher/releases/latest | grep "browser_download_url.*linux_amd64.tar.gz" | cut -d '"' -f 4)
        wget -q "$RELEASE_URL"
        tar -xzf upgopher_*_linux_amd64.tar.gz
        mv upgopher_*_linux_amd64/* .
        rmdir upgopher_*_linux_amd64
        rm -f upgopher_*_linux_amd64.tar.gz
        chmod +x upgopher
        msg_info "Starting Services"
        systemctl start upgopher
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9090${CL}"
