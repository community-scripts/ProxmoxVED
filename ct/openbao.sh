#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: gpt-5-codex
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/openbao/openbao

# App Default Values
APP="OpenBao"
# Name of the app (e.g. Google, Adventurelog, Apache-Guacamole")
var_tags="secrets;vault"
# Tags for Proxmox VE, maximum 2 pcs., no spaces allowed, separated by a semicolon ; (e.g. database | adblock;dhcp)
var_cpu="2"
# Number of cores (1-X) (e.g. 4) - default are 2
var_ram="2048"
# Amount of used RAM in MB (e.g. 2048 or 4096)
var_disk="10"
# Amount of used disk space in GB (e.g. 4 or 10)
var_os="debian"
# Default OS (e.g. debian, ubuntu, alpine)
var_version="13"
# Default OS version (e.g. 12 for debian, 24.04 for ubuntu, 3.20 for alpine)
var_unprivileged="1"
# 1 = unprivileged container, 0 = privileged container

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /usr/local/bin/openbao ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    RELEASE=$(curl -fsSL https://api.github.com/repos/openbao/openbao/releases/latest | jq -r '.tag_name' | sed 's/^v//')
    if [[ -z "${RELEASE}" ]]; then
        msg_error "Unable to determine the latest release version."
        exit 1
    fi

    CURRENT_VERSION="$(cat /opt/${APP}_version.txt 2>/dev/null || echo '')"

    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "${CURRENT_VERSION}" ]]; then
        msg_info "Updating ${APP} to v${RELEASE}"

        msg_info "Stopping $APP"
        systemctl stop openbao
        msg_ok "Stopped $APP"

        TMP_DIR="$(mktemp -d)"

        msg_info "Creating Backup"
        tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" \
            /etc/openbao /var/lib/openbao /var/log/openbao
        msg_ok "Backup Created"

        curl -fsSL "https://github.com/openbao/openbao/releases/download/v${RELEASE}/openbao_${RELEASE}_linux_amd64.zip" \
            -o "${TMP_DIR}/openbao.zip"
        unzip -qo "${TMP_DIR}/openbao.zip" -d "${TMP_DIR}"
        install -m 0755 "${TMP_DIR}/openbao" /usr/local/bin/openbao
        setcap cap_ipc_lock=+ep /usr/local/bin/openbao

        msg_info "Starting $APP"
        systemctl start openbao
        msg_ok "Started $APP"

        msg_info "Cleaning Up"
        rm -rf "${TMP_DIR}"
        msg_ok "Cleanup Completed"

        echo "${RELEASE}" >/opt/${APP}_version.txt
        msg_ok "Update Successful"
    else
        msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8200${CL}"
