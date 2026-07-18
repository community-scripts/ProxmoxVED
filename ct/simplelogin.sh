#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/simple-login/app

APP="SimpleLogin"
var_tags="${var_tags:-email;privacy;alias}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/simplelogin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "simplelogin" "simple-login/app"; then
    msg_info "Stopping Services"
    systemctl stop simplelogin-webapp simplelogin-email simplelogin-job
    msg_ok "Stopped Services"

    create_backup /opt/simplelogin/.env \
                  /opt/simplelogin/dkim \
                  /opt/simplelogin/openid-rsa.key \
                  /opt/simplelogin/openid-rsa.pub \
                  /opt/simplelogin/uploads

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "simplelogin" "simple-login/app"

    msg_info "Installing Dependencies"
    cd /opt/simplelogin
    $STD uv sync --locked --no-dev
    msg_ok "Installed Dependencies"

    msg_info "Running Database Migrations"
    cd /opt/simplelogin
    cp /opt/simplelogin_env.bak /opt/simplelogin/.env
    $STD .venv/bin/alembic upgrade head
    msg_ok "Ran Database Migrations"

    restore_backup

    msg_info "Starting Services"
    systemctl start simplelogin-webapp simplelogin-email simplelogin-job
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
