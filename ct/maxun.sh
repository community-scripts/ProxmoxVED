#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

APP="Maxun"
var_tags="${var_tags:-automation;scraper}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /opt/maxun ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "maxun" "getmaxun/maxun"; then
    msg_info "Stopping Services"
    systemctl stop maxun
    msg_ok "Services stopped"

    msg_info "Backing up Configuration"
    cp /opt/maxun/.env /tmp/maxun.env.bak
    msg_ok "Configuration backed up"

    msg_info "Updating ${APP}"
    rm -rf /opt/maxun
    fetch_and_deploy_gh_release "maxun" "getmaxun/maxun" "source"
    cp /tmp/maxun.env.bak /opt/maxun/.env
    rm -f /tmp/maxun.env.bak

    cd /opt/maxun
    $STD npm install --legacy-peer-deps
    cd /opt/maxun/maxun-core
    $STD npm install --legacy-peer-deps
    cd /opt/maxun
    $STD npx playwright install --with-deps chromium
    $STD npm run build:server
    $STD npm run build

    cp -r /opt/maxun/dist/* /var/www/maxun/
    echo "${RELEASE}" >/opt/maxun_version.txt
    msg_ok "Updated ${APP}"

    msg_info "Starting Services"
    systemctl start maxun
    msg_ok "Services started"

    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at the latest version."
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
echo -e "${INFO}${YW} MinIO Console:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9001${CL}"
echo -e "${INFO}${YW} Credentials saved in:${CL}"
echo -e "${TAB}/root/maxun.creds"
