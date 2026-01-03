#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: snazzybean
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/TomBursch/kitchenowl

APP="KitchenOwl"
var_tags="${var_tags:-food;recipes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
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

  if [[ ! -d /opt/kitchenowl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop kitchenowl
  msg_ok "Stopped Service"

  msg_info "Updating KitchenOwl"
  mkdir -p /opt/kitchenowl_backup
  cp -r /opt/kitchenowl/data /opt/kitchenowl_backup/
  cp -f /opt/kitchenowl/kitchenowl.env /opt/kitchenowl_backup/

  CLEAN_INSTALL=1 fetch_and_deploy_gh_release "kitchenowl" "TomBursch/kitchenowl" "tarball" "latest" "/opt/kitchenowl"
  sed -i 's/default=True/default=False/' /opt/kitchenowl/backend/wsgi.py
  CLEAN_INSTALL=1 fetch_and_deploy_gh_release "kitchenowl-web" "TomBursch/kitchenowl" "prebuild" "latest" "/opt/kitchenowl/web" "kitchenowl_Web.tar.gz"

  cp -r /opt/kitchenowl_backup/data /opt/kitchenowl/
  cp -f /opt/kitchenowl_backup/kitchenowl.env /opt/kitchenowl/
  rm -rf /opt/kitchenowl_backup
  msg_ok "Updated KitchenOwl"

  msg_info "Installing Dependencies"
  cd /opt/kitchenowl/backend
  $STD uv sync --frozen
  msg_ok "Dependencies installed"

  msg_info "Running Database Migrations"
  cd /opt/kitchenowl/backend
  set -a
  source /opt/kitchenowl/kitchenowl.env
  set +a
  $STD uv run flask db upgrade
  msg_ok "Database Migrations Complete"

  systemctl start kitchenowl

  msg_ok "Updated Successfully"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
