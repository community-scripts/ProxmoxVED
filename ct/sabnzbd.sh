#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://sabnzbd.org/

APP="SABnzbd"
var_tags="${var_tags:-downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
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
    if [[ ! -d /opt/sabnzbd ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    RELEASE=$(curl -fsSL https://api.github.com/repos/sabnzbd/sabnzbd/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        if [[ ! -d /opt/sabnzbd/venv ]]; then
            msg_info "Migrating SABnzbd to venv installation"
            python3 -m venv /opt/sabnzbd/venv
            source /opt/sabnzbd/venv/bin/activate
            pip install --upgrade pip
            if [[ -f /opt/sabnzbd/requirements.txt ]]; then
                pip install -r /opt/sabnzbd/requirements.txt
            fi
            deactivate
            if grep -q "ExecStart=python3 SABnzbd.py" /etc/systemd/system/sabnzbd.service; then
                sed -i "s|ExecStart=python3 SABnzbd.py|ExecStart=/opt/sabnzbd/venv/bin/python SABnzbd.py|" /etc/systemd/system/sabnzbd.service
                systemctl daemon-reload
                systemctl restart sabnzbd.service
                msg_ok "Migrated SABnzbd to venv installation and updated Service"
            fi
        fi

        msg_info "Updating $APP to ${RELEASE}"
        systemctl stop sabnzbd.service
        tar zxvf <(curl -fsSL https://github.com/sabnzbd/sabnzbd/releases/download/$RELEASE/SABnzbd-${RELEASE}-src.tar.gz)
        cp -rf SABnzbd-${RELEASE}/* /opt/sabnzbd
        rm -rf SABnzbd-${RELEASE}

        source /opt/sabnzbd/venv/bin/activate
        pip install --upgrade pip
        pip install -r /opt/sabnzbd/requirements.txt
        deactivate

        echo "${RELEASE}" >/opt/${APP}_version.txt
        systemctl start sabnzbd
        msg_ok "Updated ${APP} to ${RELEASE}"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7777${CL}"
