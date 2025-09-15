#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: dkuku
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/livebook-dev/livebook

APP="Livebook"
var_tags="${var_tags:-development}"
var_disk="${var_disk:-4}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
init_error_traps

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /opt/livebook/.mix/escripts/livebook ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    if check_for_gh_release "livebook" "livebook-dev/livebook"; then
        msg_info "Stopping ${APP}"
        systemctl stop livebook
        msg_info "Service stopped"

        msg_info "Updating container"
        $STD apt-get update
        $STD apt-get -y upgrade
        msg_ok "Updated container"

        msg_info "Updating ${APP}"
        source /opt/livebook/.env
        cd /opt/livebook
        $STD mix escript.install hex livebook --force

        chown -R livebook:livebook /opt/livebook /data
        systemctl start livebook
        msg_ok "Updated ${APP}"
    fi
    exit
}

start
build_container
description

echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
