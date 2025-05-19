#!/usr/bin/env bash
source <(curl -s https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

## App Default Values
APP="Koel"
var_tags="${var_tags:-music}"
var_disk="${var_disk:-9}"
var_cpu="${var_cpu:-3}"
var_ram="${var_ram:-3072}"
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
  if [[ ! -d /opt/koel ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -s https://api.github.com/repos/koel/koel/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping ${APP} Service"
    systemctl stop nginx
    msg_ok "Stopped ${APP} Service"

    msg_info "Updating ${APP} to v${RELEASE}"
    cd /opt
    curl -fsSL https://github.com/koel/koel/releases/download/${RELEASE}/koel-${RELEASE}.zip
    unzip -q koel-${RELEASE}.zip
    cd /opt/koel
    composer update --no-interaction >/dev/null 2>&1
    composer install --no-interaction >/dev/null 2>&1
    php artisan migrate --force >/dev/null 2>&1
    php artisan cache:clear >/dev/null 2>&1
    php artisan config:clear >/dev/null 2>&1
    php artisan view:clear >/dev/null 2>&1
    php artisan koel:init --no-interaction >/dev/null 2>&1
    msg_ok "Updated ${APP} to v${RELEASE}"

    msg_info "Starting ${APP} Service"
    systemctl start nginx
    msg_ok "Started ${APP} Service"

    msg_info "Cleaning up"
    rm -rf /opt/koel-${RELEASE}.zip
    msg_ok "Cleaned"
    msg_ok "Updated Successfully!\n"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN} ${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6767${CL}"
