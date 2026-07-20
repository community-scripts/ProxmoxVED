#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: manganate006
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/manganate006/openlmnp

APP="OpenLMNP"
var_tags="${var_tags:-accounting;finance}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
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

  if [[ ! -d /opt/openlmnp ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "openlmnp" "manganate006/openlmnp"; then
    msg_info "Stopping Services"
    systemctl stop nginx php8.4-fpm
    msg_ok "Stopped Services"

    create_backup /opt/openlmnp/.env /opt/openlmnp/database /opt/openlmnp/storage/app /opt/openlmnp/storage/logs

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "openlmnp" "manganate006/openlmnp" "tarball"

    restore_backup

    msg_info "Updating Application"
    cd /opt/openlmnp || exit
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction
    $STD npm install --no-audit --no-fund
    $STD npm run build
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    chown -R www-data:www-data /opt/openlmnp
    chmod -R 775 /opt/openlmnp/storage /opt/openlmnp/database /opt/openlmnp/bootstrap/cache
    msg_ok "Updated Application"

    msg_info "Starting Services"
    systemctl start php8.4-fpm nginx
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW} Admin credentials (generated at install) are stored in the container at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/openlmnp/admin_credentials.txt${CL}"
