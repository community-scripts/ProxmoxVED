#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.powerdns.com/

APP="PowerDNS"
var_tags="${var_tags:-dns}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
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
  if [[ ! -d /opt/poweradmin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Debian LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Debian LXC"
  cleanup_lxc
  exit
}

start
build_container
description

msg_ok "Completed successfully!"
msg_custom "🚀" "${GN}" "${APP} setup has been successfully initialized!"
