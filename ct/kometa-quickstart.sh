#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/SystemIdleProcess/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: SystemIdleProcess
# License: MIT | https://github.com/SystemIdleProcess/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Kometa-Team/Quickstart

APP="Kometa-Quickstart"
var_tags="${var_tags:-media;streaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-16}"
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

  if [[ ! -d "/opt/quickstart" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "quickstart" "Kometa-Team/Quickstart"; then
    msg_info "Stopping Service"
    systemctl stop quickstart
    msg_ok "Stopped Service"

    msg_info "Backing up data"
    cp /opt/quickstart/config/* /opt/quickstart_backup/config/ 2>/dev/null || true
    if [[ -d "/opt/quickstart/config/kometa/config" ]]; then
      cp /opt/quickstart/config/kometa/config/* /opt/kometa_backup/config/ 2>/dev/null || true
    fi
    msg_ok "Backup completed"

    PYTHON_VERSION="3.13" setup_uv
    fetch_and_deploy_gh_release "kometa-quickstart" "Kometa-Team/Quickstart" "tarball"

    msg_info "Updating Quickstart"
    cd /opt/quickstart || exit
    if [[ ! -d "/opt/quickstart/config/.venv" ]]; then
      rm -rf /opt/quickstart/config/.venv
    fi
    $STD uv venv /opt/quickstart/config/.venv
    $STD source /opt/quickstart/config/.venv/bin/activate
    $STD uv pip install --upgrade pip
    $STD uv pip install -r requirements.txt
    msg_ok "Updated Quickstart"

    msg_info "Restoring Data"
    cp /opt/quickstart_backup/config/* /opt/quickstart/config/ 2>/dev/null || true
    rm -rf /opt/quickstart_backup
    if [[ -d "/opt/kometa_backup/config" ]]; then
      cp /opt/kometa_backup/config/* /opt/quickstart/config/kometa/config/ 2>/dev/null || true
      rm -rf /opt/kometa_backup
    fi
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start quickstart
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
echo -e "${INFO}${YW} Access the LXC at following IP address:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7171${CL}"
