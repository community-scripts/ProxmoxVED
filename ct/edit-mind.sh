#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/IliasHad/edit-mind

APP="Edit-Mind"
var_tags="${var_tags:-ai;media;photos}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-32}"
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

  if [[ ! -d /opt/edit-mind ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "edit-mind" "IliasHad/edit-mind"; then
    msg_info "Stopping Services"
    systemctl stop edit-mind-web edit-mind-jobs
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/edit-mind/.env /opt/edit-mind.env.bak
    cp /opt/edit-mind/.env.system /opt/edit-mind.env.system.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "edit-mind" "IliasHad/edit-mind" "tarball"

    msg_info "Rebuilding Application"
    cd /opt/edit-mind
    $STD pnpm install --prefer-frozen-lockfile
    $STD pnpm --filter prisma generate
    $STD pnpm run build:web
    $STD pnpm rebuild @tailwindcss/oxide rollup onnxruntime-node
    $STD pnpm run build:background-jobs
    msg_ok "Rebuilt Application"

    msg_info "Restoring Data"
    cp /opt/edit-mind.env.bak /opt/edit-mind/.env
    cp /opt/edit-mind.env.system.bak /opt/edit-mind/.env.system
    rm -f /opt/edit-mind.env.bak /opt/edit-mind.env.system.bak
    msg_ok "Restored Data"

    msg_info "Running Migrations"
    cd /opt/edit-mind
    set -a && source /opt/edit-mind/.env && source /opt/edit-mind/.env.system && set +a
    $STD pnpm --filter prisma migrate:deploy
    msg_ok "Ran Migrations"

    msg_info "Starting Services"
    systemctl start edit-mind-web edit-mind-jobs
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3745${CL}"
