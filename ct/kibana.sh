#!/usr/bin/env bash
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.elastic.co/kibana

APP="Kibana"
var_tags="${var_tags:-analytics;dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export KIBANA_ES_HOSTS="${KIBANA_ES_HOSTS:-}"
export KIBANA_ES_USERNAME="${KIBANA_ES_USERNAME:-}"
export KIBANA_ES_PASSWORD="${KIBANA_ES_PASSWORD:-}"
export KIBANA_ENROLLMENT_TOKEN="${KIBANA_ENROLLMENT_TOKEN:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /usr/share/kibana ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Kibana"
  systemctl stop kibana
  msg_ok "Stopped Kibana"

  msg_info "Updating Kibana"
  $STD apt update
  $STD apt install --only-upgrade -y kibana
  msg_ok "Updated Kibana"

  msg_info "Starting Kibana"
  systemctl start kibana
  msg_ok "Started Kibana"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Web interface:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5601${CL}"
echo -e "${INFO}${YW} Configuration:${CL}"
echo -e "${TAB}${BGN}/etc/kibana/kibana.yml${CL}"
