#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/EEJoshua/ProxmoxVED/refs/heads/overleaf/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: [YourUserName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/overleaf/toolkit

APP="Overleaf"
var_tags="${var_tags:-latex;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
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
  if [[ ! -d /opt/overleaf-toolkit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP via Overleaf Toolkit"
  cd /opt/overleaf-toolkit
  git pull -q || true
  bin/upgrade || bin/up -d
  msg_ok "Update Successful"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
