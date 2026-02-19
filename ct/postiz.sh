#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: jelicanin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://docs.postiz.com/self-hosting/docker-compose

APP="Postiz"
var_tags="${var_tags:-automation;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/postiz/docker-compose.yaml ]] || [[ ! -f /opt/postiz/docker-compose.override.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  DOCKER_SKIP_UPDATES="true" setup_docker

  msg_info "Updating Compose Files"
  $STD curl -fsSL https://raw.githubusercontent.com/gitroomhq/postiz-docker-compose/main/docker-compose.yaml -o /opt/postiz/docker-compose.yaml
  mkdir -p /opt/postiz/dynamicconfig
  $STD curl -fsSL https://raw.githubusercontent.com/gitroomhq/postiz-docker-compose/main/dynamicconfig/development-sql.yaml -o /opt/postiz/dynamicconfig/development-sql.yaml
  msg_ok "Updated Compose Files"

  msg_info "Updating Postiz Containers"
  cd /opt/postiz
  $STD docker compose pull
  $STD docker compose up -d --remove-orphans
  msg_ok "Updated Postiz Containers"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4007${CL}"
