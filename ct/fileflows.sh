#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/kkroboth/ProxmoxVED/refs/heads/lxc-fileflows/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: kkroboth
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://fileflows.com/

APP="FileFlows"
var_tags="media;automation"
var_cpu="2"
var_ram="2048"
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

    # Check if installation is present | -f for file, -d for folder
    if [[ ! -d /opt/fileflows ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    UPDATE_AVAILABLE=$(curl -s -X 'GET' "http://${IP}:19200/api/status/update-available" -H 'accept: application/json' | jq .UpdateAvailable)
    if [[ "${UPDATE_AVAILABLE}" == "true" ]]; then
        msg_info "Stopping $APP"
        systemctl stop fileflows
        msg_ok "Stopped $APP"

        # Creating Backup
        msg_info "Creating Backup"
        tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" -C /opt/fileflows Data
        msg_ok "Backup Created"

        # Execute Update
        msg_info "Updating $APP to latest version"
        temp_file=$(mktemp)
        wget -q https://fileflows.com/downloads/zip -O $temp_file
        unzip -oq -d /opt/fileflows $temp_file
        chmod +x /opt/fileflows/fileflows-systemd-entrypoint.sh
        msg_ok "Updated $APP to latest version"

        # Starting Services
        msg_info "Starting $APP"
        systemctl start fileflows
        msg_ok "Started $APP"

        # Cleaning up
        msg_info "Cleaning Up"
        rm -rf $temp_file
        msg_ok "Cleanup Completed"

        # Last Action
        msg_ok "Update Successful"
    else
      msg_ok "No update required. ${APP} is already at latest version"
    fi

    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:19200${CL}"
