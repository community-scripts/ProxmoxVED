#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Andreas Schmidt (schmidtandreas)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://minecraft.net

APP="MineCraft-Bedrock"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-2}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function get_mc_br_url() {
    download_url="https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"
    index=0
    while type="$(curl -s "${download_url}" | jq -r ".result.links[${index}].downloadType")"; do
        if [[ "${type}" == "serverBedrockLinux" ]]; then
            curl -s "${download_url}" | jq -r ".result.links[${index}].downloadUrl"
            return
        fi
        index=$((index + 1))
    done
    msg_error "Couldn't find download URL!"
}

function get_mc_br_version() {
    get_mc_br_url | sed -e "s|.*bedrock-server-\(.*\)\.zip|\1|"
}

MCBR_SERVER_DIRECTORY="/minecraft"
MCBR_SERVER_VERSION_FILE="${MCBR_SERVER_DIRECTORY}/server_version.txt"
MCBR_VERSION="$(get_mc_br_version)"
MCBR_SERVER_ARCHIVE="bedrock-server-${MCBR_VERSION}.zip"

function get_local_mc_br_versoin() {
    version_file="${MCBR_SERVER_VERSION_FILE}"
    [ "${version_file}" ] && cat "${MCBR_SERVER_VERSION_FILE}" || echo ""
}

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -f /minecraft/bedrock_server ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    remote_version="${MCBR_VERSION}"
    local_version="$(get_local_mc_br_versoin)"
    if [[ "${remote_version}" != "${local_version}" ]]; then
        msg_info "Stopping ${APP}"
        systemctl stop minecraft
        msg_ok "Stopped ${APP}"

        msg_info "Updating ${APP} LXC"
        curl -s -H "user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$(get_mc_br_url)" -o "${MCBR_SERVER_ARCHIVE}"
        unzip -o -d "${MCBR_SERVER_DIRECTORY}" "${MCBR_SERVER_ARCHIVE}"
        get_mc_br_version > "${MCBR_SERVER_VERSION_FILE}"
        msg_ok "Updated ${APP} LXC"

        msg_info "Cleaning up ..."
        rm "${MCBR_SERVER_ARCHIVE}"
        msg_ok "Cleaned up"

        msg_info "Starting ${APP}"
        systemctl start minecraft
        msg_ok "Started ${APP}"
    else
        msg_ok "${APP} is up to date"
    fi
    msg_ok "Updated Successfully"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
