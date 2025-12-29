#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: KernelSailor
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://snowflake.torproject.org/

APP="tor-snowflake"
var_tags="${var_tags:-privacy;proxy;tor}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-0}"

SNOWFLAKEUSER="snowflake"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Updating Container OS"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Container OS"

  RELEASE=$(curl -fsSL https://gitlab.torproject.org/api/v4/projects/tpo%2Fanti-censorship%2Fpluggable-transports%2Fsnowflake/releases | jq -r '.[0].tag_name' | sed 's/^v//')
  VERSION_FILE="/home/${SNOWFLAKEUSER}/.${APP}_version"
  if [[ ! -f "${VERSION_FILE}" ]] || [[ "${RELEASE}" != "$(cat "${VERSION_FILE}")" ]]; then
    msg_info "Stopping ${APP} Service"
    systemctl stop ${APP}
    msg_ok "Stopped ${APP} Service"

    setup_go

    msg_info "Updating ${APP} to v${RELEASE}"
    $STD sudo -H -u ${SNOWFLAKEUSER} bash -c "cd ~ && curl -fsSL 'https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/-/archive/v${RELEASE}/snowflake-v${RELEASE}.tar.gz' -o snowflake.tar.gz"
    $STD sudo -H -u ${SNOWFLAKEUSER} bash -c "cd ~ && tar -xzf snowflake.tar.gz"
    $STD sudo -H -u ${SNOWFLAKEUSER} bash -c "cd ~ && rm snowflake.tar.gz"
    $STD sudo -H -u ${SNOWFLAKEUSER} bash -c "cd ~ && rm -rf .${APP}"
    $STD sudo -H -u ${SNOWFLAKEUSER} bash -c "cd ~ && mv snowflake-v${RELEASE} .${APP}"
    $STD sudo -H -u ${SNOWFLAKEUSER} bash -c "cd ~/.${APP}/proxy && go build -o snowflake-proxy ."
    echo "${RELEASE}" | sudo -H -u ${SNOWFLAKEUSER} bash -c "cd ~ && tee .${APP}_version >/dev/null"
    msg_ok "Updated ${APP} to v${RELEASE}"

    msg_info "Starting ${APP} Service"
    systemctl start ${APP}
    msg_ok "Started ${APP} Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}."
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
