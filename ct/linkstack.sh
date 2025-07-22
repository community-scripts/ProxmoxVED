#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya | MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://linkstack.org/

APP="LinkStack"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
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

  if [[ ! -f /.linkstack ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/linkstackorg/linkstack/releases/latest | jq -r '.tag_name | ltrimstr("v")')
  if [[ "${RELEASE}" != "$(cat ~/.linkstack 2>/dev/null)" ]] || [[ ! -f ~/.linkstack ]]; then
    msg_info "Stopping $APP"
    systemctl stop apache2
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    BACKUP_FILE="/opt/linkstack_backup_$(date +%F).tar.gz"
    $STD tar -czf "$BACKUP_FILE" /var/www/html/linkstack
    msg_ok "Backup Created"

    PHP_VERSION="8.3" PHP_MODULE="sqlite3" PHP_APACHE="YES" setup_php
    fetch_and_deploy_gh_release "linkstack" "linkstackorg/linkstack" "prebuild" "latest" "/var/www/html/linkstack" "linkstack.zip"

    msg_info "Updating $APP to v${RELEASE}"
    chown -R www-data:www-data /var/www/html/linkstack
    chmod -R 755 /var/www/html/linkstack
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start linkstack
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -rf "$BACKUP_FILE"
    msg_ok "Cleanup Completed"
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
echo -e "${INFO}${YW} Complete setup at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
