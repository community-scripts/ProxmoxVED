#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/aBat001795/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://pixelfed.org/

APP="Pixelfed"
var_tags="${var_tags:-fediverse;social}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /opt/pixelfed ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pixelfed" "pixelfed/pixelfed"; then
    msg_info "Stopping Services"
    systemctl stop pixelfed-horizon pixelfed-scheduler.timer
    msg_ok "Services stopped"

    msg_info "Backing up Configuration"
    cp /opt/pixelfed/.env /tmp/pixelfed.env.bak
    msg_ok "Configuration backed up"

    fetch_and_deploy_gh_release "pixelfed" "pixelfed/pixelfed" "tarball" "latest" "/opt/pixelfed"

    msg_info "Restoring Configuration"
    cp /tmp/pixelfed.env.bak /opt/pixelfed/.env
    rm -f /tmp/pixelfed.env.bak
    msg_ok "Configuration restored"

    msg_info "Updating Pixelfed"
    chown -R pixelfed:pixelfed /opt/pixelfed
    chmod -R 755 /opt/pixelfed
    chmod -R 775 /opt/pixelfed/storage /opt/pixelfed/bootstrap/cache
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --no-ansi --no-interaction --optimize-autoloader
    $STD sudo -u pixelfed php artisan migrate --force
    $STD sudo -u pixelfed php artisan route:cache
    $STD sudo -u pixelfed php artisan view:cache
    $STD sudo -u pixelfed php artisan config:cache
    $STD sudo -u pixelfed php artisan horizon:publish
    msg_ok "Updated Pixelfed"

    msg_info "Starting Services"
    systemctl start pixelfed-horizon pixelfed-scheduler.timer
    msg_ok "Services started"
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
echo -e "${INFO}${YW} Create an admin account with:${CL}"
echo -e "${TAB}cd /opt/pixelfed && sudo -u pixelfed php artisan user:create"
echo -e "${INFO}${YW} Credentials saved in:${CL}"
echo -e "${TAB}/root/pixelfed.creds"
