#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/toeverything/AFFiNE

APP="AFFiNE"
var_tags="${var_tags:-knowledge;notes;workspace}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-12288}"
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

  if [[ ! -d /opt/affine ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "affine" "toeverything/AFFiNE"; then
    msg_info "Stopping Services"
    systemctl stop affine-web affine-worker
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp -r /root/.affine/storage /root/.affine_storage_backup 2>/dev/null || true
    cp -r /root/.affine/config /root/.affine_config_backup 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "affine_app" "toeverything/AFFiNE" "tarball" "latest" "/opt/affine"

    msg_info "Rebuilding Application"
    cd /opt/affine
    source /root/.profile
    export PATH="/root/.cargo/bin:/root/.rbenv/shims:$PATH"

    set -a && source /opt/affine/.env && set +a

    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    export VITE_CORE_COMMIT_SHA=$(get_latest_github_release "toeverything/AFFiNE")

    $STD corepack enable
    $STD corepack prepare yarn@stable --activate
    $STD yarn config set enableTelemetry 0
    $STD yarn install
    $STD yarn affine init
    $STD yarn affine build -p @affine/server-native
    $STD yarn affine build -p @affine/reader --deps
    $STD yarn affine build -p @affine/server --deps
    export NODE_OPTIONS=--max-old-space-size=6144
    $STD yarn affine build -p @affine/web --deps
    msg_info "Restoring Data"
    cp -r /root/.affine_storage_backup/. /root/.affine/storage/ 2>/dev/null || true
    cp -r /root/.affine_config_backup/. /root/.affine/config/ 2>/dev/null || true
    rm -rf /root/.affine_storage_backup /root/.affine_config_backup
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start affine-web affine-worker
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3010${CL}"
