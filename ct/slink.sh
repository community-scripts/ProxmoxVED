#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/andrii-kryvoviaz/slink

APP="Slink"
var_tags="${var_tags:-media;images;sharing}"
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

  if [[ ! -f ~/.slink ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "slink" "andrii-kryvoviaz/slink"; then
    msg_info "Stopping Services"
    systemctl stop slink-client caddy
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/slink/services/api/.env /opt/slink-api.env.bak
    mv /opt/slink/data /opt/slink-data.bak
    mv /opt/slink/images /opt/slink-images.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "slink" "andrii-kryvoviaz/slink" "tarball"

    msg_info "Building Client"
    cd /opt/slink/services/client
    $STD yarn install --frozen-lockfile --non-interactive
    $STD yarn svelte-kit sync
    NODE_OPTIONS="--max-old-space-size=2048" $STD yarn build
    msg_ok "Built Client"

    msg_info "Updating API"
    cd /opt/slink/services/api
    cp /opt/slink-api.env.bak .env
    $STD composer install --no-dev --optimize-autoloader --no-interaction
    $STD php bin/console cache:clear
    msg_ok "Updated API"

    mv /opt/slink-data.bak /opt/slink/data
    mv /opt/slink-images.bak /opt/slink/images
    rm -f /opt/slink-api.env.bak

    msg_info "Starting Services"
    systemctl start caddy slink-client
    msg_ok "Started Services"
    msg_ok "Updated ${APP}"
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
