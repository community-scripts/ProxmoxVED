#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
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

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/keycloak ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  if check_for_update "${APP}" "keycloak/keycloak"; then
    local release="$CHECK_UPDATE_RELEASE"

    msg_info "Stopping ${APP}"
    systemctl stop keycloak
    msg_ok "Stopped ${APP}"

    msg_info "Updating packages"
    apt-get update &>/dev/null
    apt-get -y upgrade &>/dev/null
    msg_ok "Updated packages"

    msg_info "Backup old Keycloak"
    cd /opt
    mv keycloak keycloak.old
    tar -czf keycloak_conf_backup.tar.gz keycloak.old/conf
    msg_ok "Backup done"

    fetch_and_deploy_gh_release "keycloak" "keycloak/keycloak" "prebuild" "$release" "/opt/keycloak" "keycloak-*.tar.gz"

    msg_info "Updating ${APP}"
    cd /opt
    mv keycloak_conf_backup.tar.gz keycloak/conf
    cp -r keycloak.old/providers keycloak
    cp -r keycloak.old/themes keycloak
    rm -rf keycloak.old
    msg_ok "Updated ${APP} LXC"

    echo "${release}" >~/.keycloak

    msg_info "Restarting Keycloak"
    systemctl restart keycloak
    msg_ok "Restarted Keycloak"
    msg_ok "Update to v${release} successful"
  fi

  exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/admin${CL}"
#echo -e "${TAB}${GN}Temporary admin user:${BL}tmpadm${CL}"
#echo -e "${TAB}${GN}Temporary admin password:${BL}admin123${CL}"
#echo -e "${INFO}${YW} If you modified ${BL}cache-ispn.xml${YW}: Re-apply your changes to the new file, otherwise leave it unchanged.${CL}"
