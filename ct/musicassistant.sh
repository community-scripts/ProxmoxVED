#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/music-assistant/server

APP="MusicAssistant"
var_tags="${var_tags:-music}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.10}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -d /opt/musicassistant ]]; then
        msg_error "No existing installation found!"
        exit 1
    fi

    msg_info "Stopping Music Assistant service"
    systemctl stop musicassistant
    msg_ok "Service stopped"

    msg_info "Updating Music Assistant files"
    cd /opt/musicassistant || exit 1
    $STD fetch_and_deploy_gh_release music-assistant/server
    msg_ok "Music Assistant files updated"

    msg_info "Updating Python virtual environment"
    source .venv/bin/activate || exit 1
    pip install --upgrade pip uv
    uv pip install .
    msg_ok "Python environment updated"

    msg_info "Restarting Music Assistant service"
    systemctl restart musicassistant
    msg_ok "Service restarted"
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8095${CL}"
