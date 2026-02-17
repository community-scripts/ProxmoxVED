#!/usr/bin/env bash
source <(curl -fsSL "${PVE_SCRIPT_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Dictionarry-Hub/profilarr

APP="Profilarr"
var_tags="${var_tags:-arr;radarr;sonarr;config}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/profilarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "profilarr" "Dictionarry-Hub/profilarr"; then
    msg_info "Stopping Service"
    systemctl stop profilarr
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    if [[ -d /opt/profilarr/data ]]; then
      cp -r /opt/profilarr/data /opt/profilarr_data_backup
    fi
    if [[ -f /opt/profilarr/.env ]]; then
      cp /opt/profilarr/.env /opt/profilarr_data_backup/.env 2>/dev/null || true
    fi
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "profilarr" "Dictionarry-Hub/profilarr"

    msg_info "Installing Python Dependencies"
    cd /opt/profilarr
    export UV_CONCURRENT_DOWNLOADS=1
    $STD uv sync --no-dev --frozen
    msg_ok "Installed Python Dependencies"

    msg_info "Building Frontend"
    if [[ -d /opt/profilarr/frontend ]]; then
      cd /opt/profilarr/frontend
      $STD npm install
      $STD npm run build
    fi
    msg_ok "Built Frontend"

    msg_info "Restoring Data"
    if [[ -d /opt/profilarr_data_backup ]]; then
      mkdir -p /opt/profilarr/data
      cp -r /opt/profilarr_data_backup/. /opt/profilarr/data
      if [[ -f /opt/profilarr_data_backup/.env ]]; then
        cp /opt/profilarr_data_backup/.env /opt/profilarr/.env
      fi
      rm -rf /opt/profilarr_data_backup
    fi
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start profilarr
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6868${CL}"

