#!/usr/bin/env bash
source <(curl -fsSL "${PVE_SCRIPT_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: SunFlowerOwl
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/haugene/docker-transmission-openvpn

APP="transmission-openvpn"
var_tags="${var_tags:-torrent;vpn}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/transmission-openvpn/ ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    msg_info "Updating Dependencies"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated Dependencies"

    if check_for_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn"; then
        msg_info "Stopping Service"
        systemctl stop openvpn-custom
        msg_ok "Stopped Service"

        msg_info "Creating Backup"
        mv /etc/openvpn/custom /opt/transmission-openvpn/
        rm -f /opt/transmission-openvpn/config-failure.sh
        msg_ok "Created Backup"

        fetch_and_deploy_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn" "tarball" "latest" "/opt/docker-transmission-openvpn"

        msg_info "Configuring transmission-openvpn"
        rm -rf /etc/openvpn/* /etc/transmission/* /etc/scripts/* /opt/privoxy/*
        cp -r /opt/docker-transmission-openvpn/openvpn/* /etc/openvpn/
        cp -r /opt/docker-transmission-openvpn/transmission/* /etc/transmission/
        cp -r /opt/docker-transmission-openvpn/scripts/* /etc/scripts/
        cp -r /opt/docker-transmission-openvpn/privoxy/scripts/* /opt/privoxy/
        chmod +x /etc/openvpn/*.sh
        chmod +x /etc/scripts/*.sh
        chmod +x /opt/privoxy/*.sh
        msg_ok "Configured transmission-openvpn"

        msg_info "Restoring Backup"
        cp -r /opt/transmission-openvpn/custom/* /etc/openvpn/custom/
        msg_ok "Restored Backup"

        msg_info "Starting Service"
        systemctl start openvpn-custom
        msg_ok "Started Service"
    fi

    msg_info "Cleaning up"
    rm -rf /opt/docker-transmission-openvpn
    msg_ok "Cleaned"
    msg_ok "Updated successfully!"
    exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9091${CL}"
