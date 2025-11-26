#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: AlphaLawless
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/alexjustesen/speedtest-tracker

APP="Speedtest-Tracker"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
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

  if [[ ! -d /opt/speedtest-tracker ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/alexjustesen/speedtest-tracker/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop speedtest-tracker
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    cp -r /opt/speedtest-tracker /opt/speedtest-tracker-backup
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    cd /opt
    rm -rf speedtest-tracker-update
    curl -fsSL "https://github.com/alexjustesen/speedtest-tracker/archive/refs/tags/v${RELEASE}.tar.gz" -o v${RELEASE}.tar.gz
    tar -xzf v${RELEASE}.tar.gz
    mv speedtest-tracker-${RELEASE} speedtest-tracker-update

    cp /opt/speedtest-tracker/.env /opt/speedtest-tracker-update/.env
    cp -r /opt/speedtest-tracker/storage/app/* /opt/speedtest-tracker-update/storage/app/ 2>/dev/null || true

    cd /opt/speedtest-tracker-update
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --optimize-autoloader --no-dev
    $STD npm ci
    $STD npm run build
    $STD php artisan migrate --force
    $STD php artisan config:clear
    $STD php artisan cache:clear
    $STD php artisan view:clear

    rm -rf /opt/speedtest-tracker
    mv /opt/speedtest-tracker-update /opt/speedtest-tracker
    chown -R www-data:www-data /opt/speedtest-tracker
    chmod -R 755 /opt/speedtest-tracker/storage
    chmod -R 755 /opt/speedtest-tracker/bootstrap/cache
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start speedtest-tracker
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -rf /opt/v${RELEASE}.tar.gz
    rm -rf /opt/speedtest-tracker-backup
    msg_ok "Cleanup Completed"

    echo "${RELEASE}" >/opt/${APP}_version.txt
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
