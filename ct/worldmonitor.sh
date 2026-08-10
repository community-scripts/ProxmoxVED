#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/shared/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/koala73/worldmonitor

APP="World Monitor"
var_tags="${var_tags:-monitoring;osint;dashboard}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/worldmonitor ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "worldmonitor" "koala73/worldmonitor"; then
    msg_info "Stopping Services"
    systemctl stop worldmonitor worldmonitor-ais-relay worldmonitor-redis-rest
    msg_ok "Stopped Services"

    create_backup /opt/worldmonitor/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "worldmonitor" "koala73/worldmonitor" "tarball" "latest" "/opt/worldmonitor"

    msg_info "Rebuilding World Monitor (Patience)"
    cd /opt/worldmonitor
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD npm ci --ignore-scripts
    $STD npm ci --prefix scripts --omit=dev --omit=optional --ignore-scripts
    $STD npm install --prefix docker redis@4
    $STD node docker/build-handlers.mjs
    $STD npm run build:crawlable-corpus
    $STD npm run build:content-corpus
    $STD npx tsc
    $STD npx vite build
    rm -rf /opt/worldmonitor/node_modules
    cp /opt/worldmonitor/docker/runtime-package.json /opt/worldmonitor/package.json
    cp /opt/worldmonitor/docker/runtime-package-lock.json /opt/worldmonitor/package-lock.json
    $STD npm ci --omit=dev --omit=optional --ignore-scripts
    msg_ok "Rebuilt World Monitor"

    restore_backup

    msg_info "Starting Services"
    systemctl start worldmonitor-redis-rest worldmonitor-ais-relay worldmonitor
    systemctl reload nginx
    msg_ok "Started Services"
    msg_ok "Updated Successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
