#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: onionrings29
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://plane.so | GitHub: https://github.com/makeplane/plane

APP="Plane"
var_tags="${var_tags:-project-management}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
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

  if [[ ! -d /opt/plane ]]; then
    msg_error "No Plane Installation Found!"
    exit
  fi

  if check_for_gh_release "plane" "makeplane/plane"; then
    msg_info "Stopping Services"
    systemctl stop plane-api plane-worker plane-beat plane-live plane-space
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/plane/apps/api/.env /opt/plane-api-env.bak
    cp /opt/plane/.env /opt/plane-live-env.bak
    cp /opt/plane/apps/web/.env /opt/plane-web-env.bak
    cp /opt/plane/apps/admin/.env /opt/plane-admin-env.bak
    cp /opt/plane/apps/space/.env /opt/plane-space-env.bak
    msg_ok "Backed up Data"

    msg_info "Updating Plane"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "plane" "makeplane/plane" "tarball"
    msg_ok "Updated Plane"

    msg_info "Restoring Config"
    cp /opt/plane-api-env.bak /opt/plane/apps/api/.env
    cp /opt/plane-live-env.bak /opt/plane/.env
    cp /opt/plane-web-env.bak /opt/plane/apps/web/.env
    cp /opt/plane-admin-env.bak /opt/plane/apps/admin/.env
    cp /opt/plane-space-env.bak /opt/plane/apps/space/.env
    rm -f /opt/plane-api-env.bak /opt/plane-live-env.bak /opt/plane-web-env.bak /opt/plane-admin-env.bak /opt/plane-space-env.bak
    msg_ok "Restored Config"

    msg_info "Rebuilding Frontend (Patience)"
    cd /opt/plane
    export NODE_OPTIONS="--max-old-space-size=4096"
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    $STD corepack enable pnpm
    $STD pnpm install --frozen-lockfile
    $STD pnpm turbo run build --filter=web --filter=admin --filter=space --filter=live
    msg_ok "Rebuilt Frontend"

    msg_info "Updating Python Dependencies"
    cd /opt/plane/apps/api
    export VIRTUAL_ENV=/opt/plane-venv
    $STD uv pip install --upgrade -r requirements/production.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Running Migrations"
    cd /opt/plane/apps/api
    set -a
    source /opt/plane/apps/api/.env
    set +a
    $STD /opt/plane-venv/bin/python manage.py migrate
    $STD /opt/plane-venv/bin/python manage.py collectstatic --noinput
    $STD /opt/plane-venv/bin/python manage.py configure_instance
    msg_ok "Ran Migrations"

    msg_info "Starting Services"
    systemctl start plane-api plane-worker plane-beat plane-live plane-space
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
