#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: masterde
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

APP="Cal.diy"
var_tags="${var_tags:-scheduling}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
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
  if [[ ! -d /opt/caldiy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" setup_nodejs

  msg_info "Stopping Service"
  systemctl stop caldiy
  msg_ok "Stopped Service"

  msg_info "Backing up configuration"
  cp /opt/caldiy/.env /opt/caldiy.env.bak
  [[ -f /opt/caldiy/.env.appStore ]] && cp /opt/caldiy/.env.appStore /opt/caldiy.env.appStore.bak
  msg_ok "Backup created"

  msg_info "Updating ${APP} (Patience, this build is heavy)"
  cd /opt/caldiy || return
  $STD git fetch --all
  $STD git reset --hard origin/main
  cp /opt/caldiy.env.bak /opt/caldiy/.env
  [[ -f /opt/caldiy.env.appStore.bak ]] && cp /opt/caldiy.env.appStore.bak /opt/caldiy/.env.appStore
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export NODE_OPTIONS="--max-old-space-size=7168"
  $STD corepack enable
  $STD yarn install
  $STD yarn workspace @calcom/prisma db-deploy
  rm -rf /opt/caldiy/apps/web/.next /opt/caldiy/.turbo
  $STD yarn build
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start caldiy
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
