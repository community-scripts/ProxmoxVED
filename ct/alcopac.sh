#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://dev.alcopa.cc/

function header_info {
clear
cat <<"EOF"
   ___    __                             
  /   |  / /________  ____  ____ ______
 / /| | / / ___/ __ \/ __ \/ __ `/ ___/
/ ___ |/ / /__/ /_/ / /_/ / /_/ / /__  
/_/  |_/_/\___/\____/ .___/\__,_/\___/  
                   /_/                  
EOF
}
header_info
echo -e "Loading..."
APP="alcopac"
var_tags="media"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_os="debian"
var_version="13"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/lampac ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi
  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
