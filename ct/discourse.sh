#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.discourse.org/

APP="Discourse"
var_tags="${var_tags:-forum;community;discussion}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
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

  if [[ ! -d /opt/discourse ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ ! -f /opt/discourse/.env ]]; then
    msg_error "No Discourse Configuration Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop discourse
  msg_ok "Stopped Service"

  msg_info "Backing up Data"
  cp /opt/discourse/.env /opt/discourse_env.bak
  msg_ok "Backed up Data"

  msg_info "Updating Discourse"
  cd /opt/discourse
  git pull origin main
  $STD bundle install --deployment --without test development
  $STD yarn install
  $STD bundle exec rails assets:precompile
  $STD bundle exec rails db:migrate
  msg_ok "Updated Discourse"

  msg_info "Restoring Configuration"
  mv /opt/discourse_env.bak /opt/discourse/.env
  msg_ok "Restored Configuration"

  msg_info "Starting Service"
  systemctl start discourse
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW} Default Credentials:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Username: admin${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Password: Check /opt/discourse/.env${CL}"
