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
  if [[ ! -f "/opt/tor-snowflake/version" ]] || [[ "${RELEASE}" != "$(cat "/opt/tor-snowflake/version")" ]]; then
    msg_info "Stopping Service"
    systemctl stop snowflake-proxy
    msg_ok "Stopped Service"

    setup_go

    msg_info "Updating Snowflake"
    $STD bash -c "cd /opt && curl -fsSL 'https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/-/archive/v${RELEASE}/snowflake-v${RELEASE}.tar.gz' -o snowflake.tar.gz"
    $STD bash -c "cd /opt && tar -xzf snowflake.tar.gz"
    $STD rm -rf /opt/snowflake.tar.gz
    $STD rm -rf /opt/tor-snowflake
    $STD mv /opt/snowflake-v${RELEASE} /opt/tor-snowflake
    $STD chown -R snowflake:snowflake /opt/tor-snowflake
    $STD sudo -H -u snowflake bash -c "cd /opt/tor-snowflake/proxy && go build -o snowflake-proxy ."
    echo "${RELEASE}" >/opt/tor-snowflake/version
    msg_ok "Updated Snowflake to v${RELEASE}"

    msg_info "Starting Service"
    systemctl start snowflake-proxy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. Snowflake is already at v${RELEASE}."
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
