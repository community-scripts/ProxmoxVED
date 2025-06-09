#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://maybefinance.com

APP="Maybe Finance"
var_tags="${var_tags:-finance;budget}"
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

  if [[ ! -d /opt/maybe ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -s https://api.github.com/repos/maybe-finance/maybe/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ "${RELEASE}" != "$(cat /opt/maybe_version.txt)" ]] || [[ ! -f /opt/maybe_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop maybe-web maybe-worker
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    cp /opt/maybe/.env /opt/maybe.env
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    rm -rf /opt/maybe
    curl -fsSL "https://github.com/maybe-finance/maybe/archive/refs/tags/v${RELEASE}.zip" -o /tmp/v"$RELEASE".zip
    unzip -q /tmp/v"$RELEASE".zip
    mv maybe-"$RELEASE" /opt/maybe
    cd /opt/maybe
    source ~/.profile
    $STD ./bin/bundle install
    $STD ./bin/bundle exec bootsnap precompile --gemfile -j 0
    $STD ./bin/bundle exec bootsnap precompile -j 0 app/ lib/
    export SECRET_KEY_BASE_DUMMY=1
    $STD ./bin/rails assets:precompile
    $STD dotenv -f ./.env ./bin/rails db:prepare
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start maybe-worker maybe-web
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm /tmp/v"$RELEASE".zip
    msg_ok "Cleanup Completed"

    echo "${RELEASE}" >/opt/maybe_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
