#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source:

APP="Roundcubemail"
var_tags="${var_tags:-mail}"
var_disk="${var_disk:-5}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    if [[ ! -d /opt/roundcubemail ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    if (($(df /boot | awk 'NR==2{gsub("%","",$5); print $5}') > 80)); then
        read -r -p "Warning: Storage is dangerously low, continue anyway? <y/N> " prompt
        [[ ${prompt,,} =~ ^(y|yes)$ ]] || exit
    fi
    RELEASE=$(curl -fsSL https://api.github.com/repos/roundcube/roundcubemail/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        msg_info "Updating ${APP} to ${RELEASE}"
        cd /opt
        curl -fsSL "https://github.com/roundcube/roundcubemail/releases/download/${RELEASE}/roundcubemail-${RELEASE}-complete.tar.gz"
        tar -xf roundcubemail-${RELEASE}-complete.tar.gz
        mv roundcubemail-${RELEASE} /opt/roundcubemail
        cd /opt/roundcubemail
        COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev
        chown -R www-data:www-data temp/ logs/
        msg_ok "Updated ${APP}"

        msg_info "Reload Apache2"
        systemctl reload apache2
        msg_ok "Apache2 Reloaded"

        msg_info "Cleaning Up"
        rm -rf /opt/roundcubemail-${RELEASE}-complete.tar.gz
        msg_ok "Cleaned"
        msg_ok "Updated Successfully"
    else
        msg_ok "No update required. ${APP} is already at ${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}/installer ${CL} \n"
