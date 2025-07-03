#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster) | Co-Author: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.keycloak.org/

APP="Keycloak"
var_tags="${var_tags:-access-management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"
var_postfix_sat="${var_postfix_sat:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -f /etc/systemd/system/keycloak.service ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    
	msg_info "Stopping ${APP}"
    systemctl stop keycloak
	msg_ok "Stopped ${APP}"

    msg_info "Updating packages"
    apt-get update &>/dev/null
    apt-get -y upgrade &>/dev/null
	msg_ok "Updated packages"

    RELEASE=$(curl -fsSL https://api.github.com/repos/keycloak/keycloak/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    msg_info "Updating ${APP} to v$RELEASE"
    cd /opt
    wget -q https://github.com/keycloak/keycloak/releases/download/$RELEASE/keycloak-$RELEASE.tar.gz
    mv keycloak keycloak.old
    tar -xzf keycloak-$RELEASE.tar.gz
    tar -czf keycloak_conf_backup.tar.gz keycloak.old/conf
    mv keycloak_conf_backup.tar.gz keycloak-$RELEASE/conf
    cp -r keycloak.old/providers keycloak-$RELEASE
    cp -r keycloak.old/themes keycloak-$RELEASE
    mv keycloak-$RELEASE keycloak
    rm keycloak-$RELEASE.tar.gz
    rm -rf keycloak.old
	msg_ok "Updated ${APP} LXC"

    msg_info "Restating Keycloak"
    systemctl restart keycloak
    msg_ok "Restated Keycloak"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/admin${CL}"
echo -e "${TAB}${GN}Temporary admin user:${BL}tmpadm${CL}"
echo -e "${TAB}${GN}Temporary admin password:${BL}admin123${CL}"
echo -e "${INFO}${YW} If you modified configurations files in `conf/`: Re-apply your changes to those files, otherwise leave them unchanged.${CL}"
