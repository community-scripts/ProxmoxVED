#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Åsbjørn Hansen (asbjornhansen)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://taskosaur.com/ | Github: https://github.com/Taskosaur/Taskosaur

APP="Taskosaur"
var_tags="${var_tags:-project-management;tasks;ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
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

  if [[ ! -d /opt/taskosaur ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_tag "taskosaur" "Taskosaur/Taskosaur"; then
    msg_info "Stopping Service"
    systemctl stop taskosaur
    msg_ok "Stopped Service"

    create_backup /opt/taskosaur/.env \
      /opt/taskosaur/uploads
    CLEAN_INSTALL=1 fetch_and_deploy_gh_tag "taskosaur" "Taskosaur/Taskosaur" "$CHECK_UPDATE_RELEASE"
    restore_backup

    NODE_VERSION="22" setup_nodejs

    msg_info "Updating Taskosaur"
    cd /opt/taskosaur || exit
    set -a
    source /opt/taskosaur/.env
    set +a
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD npm install
    $STD npm run build:dist
    cd /opt/taskosaur/dist || exit
    $STD npm run prisma:generate
    $STD npm run prisma:migrate:deploy
    rm -rf /opt/taskosaur/node_modules
    msg_ok "Updated Taskosaur"

    msg_info "Starting Service"
    systemctl start taskosaur
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
