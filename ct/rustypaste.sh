#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/GoldenSpringness/ProxmoxVED/refs/heads/feature/rustypaste/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: GoldenSpringness
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

# App Default Values
APP="rustypaste"
var_tags="${var_tags:-pastebin;storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-20}"
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

    # Check if installation is present | -f for file, -d for folder
    if [[ ! -f "/opt/${APP}/target/release/rustypaste" ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    # Crawling the new version and checking whether an update is required
    RELEASE=$(curl -s https://api.github.com/repos/orhun/rustypaste/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
        # Stopping Services
        msg_info "Stopping $APP"
        systemctl stop ${APP}
        msg_ok "Stopped $APP"

        # Creating Backup
        msg_info "Creating Backup"
        tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" "/opt/${APP}/upload" # Backing up full project + all bins
        msg_ok "Backup Created"

        # Execute Update
        msg_info "Updating $APP to ${RELEASE}"
        cd /opt/rustypaste

        git fetch --tags # getting newest versions
        git switch --detach ${RELEASE}

        cargo build --locked --release # recreating the binary
        msg_ok "Updated $APP to ${RELEASE}"

        # Starting Services
        msg_info "Starting $APP"
        systemctl start ${APP}
        msg_ok "Started $APP"

        # Last Action
        echo "${RELEASE}" > /opt/${APP}_version.txt
        msg_ok "Update Successful"
    else
        msg_ok "No update required. ${APP} is already at ${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
