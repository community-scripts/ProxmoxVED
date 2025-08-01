#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/maxdorninger/MediaManager

APP="MediaManager"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
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
  if [[ ! -d /opt/mediamanager ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/maxdorninger/MediaManager/releases/latest | yq '.tag_name' | sed 's/^v//')
  if [[ "${RELEASE}" != "$(cat ~/.mediamanager 2>/dev/null)" ]] || [[ ! -f ~/.mediamanager ]]; then
    msg_info "Stopping Service"
    systemctl stop mediamanager
    msg_ok "Stopped Service"

    msg_info "Updating ${APP}"
    fetch_and_deploy_gh_release "MediaManager" "maxdorninger/MediaManager" "tarball" "latest" "/opt/mediamanager"
    MM_DIR="/opt/mm"
    export CONFIG_DIR="${MM_DIR}/config"
    export FRONTEND_FILES_DIR="${MM_DIR}/web/build"
    export BASE_PATH=""
    export PUBLIC_VERSION=""
    export PUBLIC_API_URL="${BASE_PATH}/api/v1"
    export BASE_PATH="${BASE_PATH}/web"
    cd /opt/mediamanager/web
    $STD npm ci
    $STD npm run build
    rm -rf "$FRONTEND_FILES_DIR"/build
    cp -r build "$FRONTEND_FILES_DIR"

    export BASE_PATH=""
    export VIRTUAL_ENV="/opt/${MM_DIR}/venv"
    cd /opt/mediamanager
    rm -rf "$MM_DIR"/{media_manager,alembic*}
    cp -r {media_manager,alembic*} "$MM_DIR"
    $STD /usr/local/bin/uv sync --locked --active
    msg_ok "Updated $APP"

    msg_info "Starting Service"
    systemctl start mediamanager
    msg_ok "Started Service"

    msg_ok "Updated Successfully"
  else
    msg_ok "Already up to date"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
