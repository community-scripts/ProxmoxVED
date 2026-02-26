#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/onionrings29/ProxmoxVE/feat/add-plane/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: onionrings29
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://plane.so

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
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "plane" "makeplane/plane"; then
    msg_info "Stopping Services"
    systemctl stop plane-api plane-worker plane-beat plane-live
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/plane/apps/api/.env /opt/plane-env.bak
    msg_ok "Backed up Data"

    msg_info "Downloading Update"
    RELEASE=$(get_latest_github_release "makeplane/plane")
    curl -fsSL "https://github.com/makeplane/plane/archive/refs/tags/v${RELEASE}.tar.gz" -o /tmp/plane.tar.gz
    tar -xzf /tmp/plane.tar.gz -C /tmp
    rm -rf /opt/plane/apps /opt/plane/packages /opt/plane/package.json /opt/plane/pnpm-lock.yaml /opt/plane/pnpm-workspace.yaml /opt/plane/turbo.json
    cp -r /tmp/plane-*/apps /opt/plane/
    cp -r /tmp/plane-*/packages /opt/plane/
    cp /tmp/plane-*/package.json /opt/plane/
    cp /tmp/plane-*/pnpm-lock.yaml /opt/plane/
    cp /tmp/plane-*/pnpm-workspace.yaml /opt/plane/
    cp /tmp/plane-*/turbo.json /opt/plane/
    rm -rf /tmp/plane.tar.gz /tmp/plane-*
    msg_ok "Downloaded Update"

    msg_info "Restoring Config"
    cp /opt/plane-env.bak /opt/plane/apps/api/.env
    rm /opt/plane-env.bak
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
    $STD /opt/plane-venv/bin/pip install --upgrade -r requirements/production.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Running Migrations"
    cd /opt/plane/apps/api
    set -a
    source /opt/plane/apps/api/.env
    set +a
    $STD /opt/plane-venv/bin/python manage.py migrate
    $STD /opt/plane-venv/bin/python manage.py collectstatic --noinput
    msg_ok "Ran Migrations"

    echo "${RELEASE}" >/opt/plane_version.txt

    msg_info "Starting Services"
    systemctl start plane-api plane-worker plane-beat plane-live
    msg_ok "Started Services"

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
