#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/prop4n/ProxmoxVED/refs/heads/add-script-sonarqube/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: prop4n
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.sonarsource.com/sonarqube-server

APP="SonarQube"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-25}"
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
    if [[ ! -d /opt/sonarqube ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    RELEASE=$(curl -s https://api.github.com/repos/SonarSource/sonarqube/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
      msg_info "Updating ${APP} to v${RELEASE}"

      systemctl stop sonarqube

      BACKUP_DIR="/opt/sonarqube-backup"
      mv /opt/sonarqube ${BACKUP_DIR}

      curl -fsSL -o /tmp/sonarqube.zip "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${RELEASE}.zip"

      mkdir -p /opt/sonarqube

      unzip -q /tmp/sonarqube.zip -d /tmp
      cp -r /tmp/sonarqube-${RELEASE}/* /opt/sonarqube/
      rm -rf /tmp/sonarqube*

      cp -rp ${BACKUP_DIR}/data/ /opt/sonarqube/data/
      cp -rp ${BACKUP_DIR}/extensions/ /opt/sonarqube/extensions/
      cp -p ${BACKUP_DIR}/conf/sonar.properties /opt/sonarqube/conf/sonar.properties
      rm -rf ${BACKUP_DIR}

      chown -R sonarqube:sonarqube /opt/sonarqube

      echo "${RELEASE}" > /opt/${APP}_version.txt

      systemctl start sonarqube

      msg_ok "Updated to v${RELEASE}"
    else
      msg_ok "No update required. ${APP} is already at v${RELEASE}."
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"
echo -e "${YW}Default credentials:${CL}"
echo -e "${TAB}Username: admin"
echo -e "${TAB}Password: admin"
