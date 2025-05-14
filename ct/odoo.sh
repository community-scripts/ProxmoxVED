#!/usr/bin/env bash
source <(curl -s https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/odoo/odoo

APP="Odoo"
# shellcheck disable=SC2034
var_tags="${var_tags:-erp}"
var_disk="${var_disk:-6}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
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

  if [[ ! -d /opt/odoo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  RELEASE="17.0"
  if [[ ! -f /opt/odoo_version.txt ]] || [[ "$RELEASE" != "$(cat /opt/odoo_version.txt)" ]]; then
    msg_info "Stopping ${APP} service"
    systemctl stop odoo
    msg_ok "Stopped ${APP}"

    msg_info "Updating ${APP} to ${RELEASE}"
    cd /opt
    rm -rf odoo_bak
    mv odoo odoo_bak
    git clone --depth 1 --branch "$RELEASE" https://github.com/odoo/odoo.git /opt/odoo/odoo
    cd /opt/odoo
    /opt/odoo/venv/bin/pip install -r /opt/odoo/odoo/requirements.txt
    echo "$RELEASE" >/opt/odoo_version.txt
    msg_ok "Updated ${APP} to ${RELEASE}"

    msg_info "Starting ${APP} service"
    systemctl start odoo
    msg_ok "Started ${APP}"

    msg_info "Cleaning Up"
    rm -rf /opt/odoo_bak
    msg_ok "Cleaned"

    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8069${CL}"
