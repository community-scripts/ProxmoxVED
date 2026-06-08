#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Indigo (alexindigo)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Crosstalk-Solutions/project-nomad | https://www.projectnomad.us

APP="Nomad"
var_tags="${var_tags:-offline;knowledge;education;ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_gpu="${var_gpu:-yes}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/project-nomad ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nomad" "Crosstalk-Solutions/project-nomad"; then
    msg_info "Updating Nomad"
    cd /opt/project-nomad

    APP_KEY=$(grep 'APP_KEY=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*APP_KEY=//')
    DB_PASS=$(grep 'DB_PASSWORD=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*DB_PASSWORD=//')
    DB_ROOT_PASS=$(grep 'MYSQL_ROOT_PASSWORD=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*MYSQL_ROOT_PASSWORD=//')
    DB_USER_PASS=$(grep 'MYSQL_PASSWORD=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*MYSQL_PASSWORD=//')
    NOMAD_URL=$(grep 'URL=' /opt/project-nomad/compose.yml | head -1 | sed 's/.*URL=//')

    fetch_and_deploy_gh_release "nomad" "Crosstalk-Solutions/project-nomad" "tarball"

    cp /opt/nomad/install/management_compose.yaml /opt/project-nomad/compose.yml
    cp /opt/nomad/install/start_nomad.sh /opt/project-nomad/start_nomad.sh
    cp /opt/nomad/install/stop_nomad.sh /opt/project-nomad/stop_nomad.sh
    cp /opt/nomad/install/update_nomad.sh /opt/project-nomad/update_nomad.sh
    chmod +x /opt/project-nomad/*.sh

    sed -i "s|URL=replaceme|URL=${NOMAD_URL}|g" /opt/project-nomad/compose.yml
    [[ -n "$APP_KEY" ]] && sed -i "s|APP_KEY=replaceme|APP_KEY=${APP_KEY}|g" /opt/project-nomad/compose.yml
    [[ -n "$DB_PASS" ]] && sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${DB_PASS}|g" /opt/project-nomad/compose.yml
    [[ -n "$DB_ROOT_PASS" ]] && sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}|g" /opt/project-nomad/compose.yml
    [[ -n "$DB_USER_PASS" ]] && sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${DB_USER_PASS}|g" /opt/project-nomad/compose.yml
    sed -i 's|"8080:8080"|"80:8080"|g' /opt/project-nomad/compose.yml

    $STD docker compose pull
    $STD docker compose up -d --force-recreate
    msg_ok "Updated Successfully"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
