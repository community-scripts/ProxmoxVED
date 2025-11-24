#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/manyfold3d/manyfold

APP="Manyfold"
var_tags="${var_tags:-3d}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/manyfold ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    if check_for_gh_release "manyfold" "manyfold3d/manyfold"; then
        msg_info "Stopping Service"
        systemctl stop manyfold manyfold-rails manyfold-default_worker manyfold-performance_worker
        msg_ok "Stopped Service"

        fetch_and_deploy_gh_release "manyfold" "manyfold3d/manyfold" "tarball" "latest" "/opt/manyfold/app"

        msg_info "Update services"
        $STD foreman export systemd /etc/systemd/system -a manyfold -u root -f /opt/manyfold/Procfile
        for f in /etc/systemd/system/manyfold-*.service; do
            sed -i "s|/bin/bash -lc '|/bin/bash -lc 'source /opt/.env \&\& |" "$f"
        done
        msg_ok "Updated services"

        msg_info "Starting Service"
        systemctl start manyfold manyfold-rails manyfold-default_worker manyfold-performance_worker
        msg_ok "Started Service"
    fi

    msg_info "Cleaning up"
    $STD apt -y autoremove
    $STD apt -y autoclean
    $STD apt -y clean
    msg_ok "Cleaned"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
