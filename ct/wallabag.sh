#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://wallabag.org/

# App Default Values
APP="Wallabag"
var_tags="${var_tags:-productivity;read-it-later}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/wallabag ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/wallabag/wallabag/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt 2>/dev/null)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping Services"
    systemctl stop nginx
    systemctl stop php8.3-fpm
    msg_ok "Stopped Services"

    msg_info "Backing up Wallabag"
    cp /opt/wallabag/app/config/parameters.yml /tmp/wallabag_parameters.yml.bak
    msg_ok "Backed up Configuration"

    msg_info "Updating $APP to v${RELEASE}"
    cd /tmp
    wget -q "https://github.com/wallabag/wallabag/releases/download/${RELEASE}/wallabag-${RELEASE#v}.tar.gz"
    tar -xzf "wallabag-${RELEASE#v}.tar.gz"

    rm -rf /opt/wallabag/vendor /opt/wallabag/var/cache/*
    cp -rf wallabag-${RELEASE#v}/* /opt/wallabag/

    cp /tmp/wallabag_parameters.yml.bak /opt/wallabag/app/config/parameters.yml

    cd /opt/wallabag
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction
    $STD php bin/console cache:clear --env=prod
    $STD php bin/console doctrine:migrations:migrate --env=prod --no-interaction

    chown -R wallabag:wallabag /opt/wallabag
    chmod -R 755 /opt/wallabag/var
    chmod -R 755 /opt/wallabag/web/assets

    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Cleaning Up"
    rm -rf /tmp/wallabag-${RELEASE#v}*
    rm -f /tmp/wallabag_parameters.yml.bak
    msg_ok "Cleanup Completed"

    msg_info "Starting Services"
    systemctl start php8.3-fpm
    systemctl start nginx
    msg_ok "Started Services"

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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
