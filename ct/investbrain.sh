#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Benito Rodríguez (b3ni)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/investbrainapp/investbrain

APP="Investbrain"
var_tags="${var_tags:-finance;portfolio;investing}"
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

  if [[ ! -d /opt/investbrain ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PG_VERSION="17" setup_postgresql

  if check_for_gh_release "Investbrain" "investbrainapp/investbrain"; then
    msg_info "Stopping Services"
    systemctl stop nginx
    systemctl stop php8.4-fpm
    supervisorctl stop all
    msg_ok "Services Stopped"

    msg_info "Creating Backup"
    rm -f /opt/.env.backup
    rm -rf /opt/storage.backup
    cp /opt/investbrain/.env /opt/.env.backup
    cp -r /opt/investbrain/storage /opt/storage.backup
    msg_ok "Created Backup"

    msg_info "Updating Investbrain"
    rm -rf /opt/investbrain-new
    mkdir -p /opt/investbrain-new
    fetch_and_deploy_gh_release "Investbrain" "investbrainapp/investbrain" "tarball" "latest" "/opt/investbrain-new"

    cd /opt/investbrain
    cp -r /opt/investbrain-new/* /opt/investbrain/
    rm -rf /opt/investbrain/storage
    rm -rf /opt/investbrain-new

    cp /opt/.env.backup /opt/investbrain/.env
    cp -r /opt/storage.backup/ /opt/investbrain/storage

    chown -R www-data:www-data /opt/investbrain
    chmod -R 775 /opt/investbrain/storage
    mkdir -p /opt/investbrain/storage/framework/cache/data
    mkdir -p /opt/investbrain/storage/framework/sessions
    mkdir -p /opt/investbrain/storage/framework/views
    mkdir -p /opt/investbrain/storage/logs
    mkdir -p /opt/investbrain/bootstrap/cache
    chown -R www-data:www-data /opt/investbrain/{storage,bootstrap/cache}

    PHP_VERSION="8.4" PHP_FPM=YES PHP_MODULE="gd,zip,intl,pdo,pgsql,pdo-pgsql,bcmath,opcache,mbstring,redis" setup_php
    setup_composer

    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-interaction --no-dev --optimize-autoloader

    $STD npm install
    $STD npm run build

    $STD php artisan storage:link
    $STD php artisan migrate --force

    $STD php artisan cache:clear
    $STD php artisan view:clear
    $STD php artisan route:clear
    $STD php artisan event:clear
    $STD php artisan route:cache
    $STD php artisan event:cache

    chown -R www-data:www-data /opt/investbrain
    chmod -R 755 /opt/investbrain/storage /opt/investbrain/bootstrap/cache

    rm -rf /opt/.env.backup /opt/storage.backup
    msg_ok "Updated Investbrain"

    msg_info "Starting Services"
    systemctl start php8.4-fpm
    systemctl start nginx
    supervisorctl start all
    msg_ok "Services Started"

    msg_ok "Updated Successfully!"
  else
    msg_ok "No update available"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
