#!/usr/bin/env bash
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.elastic.co/elasticsearch

APP="Elasticsearch"
var_tags="${var_tags:-database;search}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /usr/share/elasticsearch ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Elasticsearch"
  systemctl stop elasticsearch
  msg_ok "Stopped Elasticsearch"

  msg_info "Updating Elasticsearch"
  $STD apt update
  $STD apt install --only-upgrade -y elasticsearch
  msg_ok "Updated Elasticsearch"

  msg_info "Starting Elasticsearch"
  systemctl start elasticsearch
  msg_ok "Started Elasticsearch"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} HTTP endpoint:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:9200${CL}"
echo -e "${INFO}${YW} Credentials (user 'elastic'):${CL}"
echo -e "${TAB}${BGN}/root/elasticsearch.creds${CL}"
