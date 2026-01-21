#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.mailpiler.org/

APP="Piler"
var_tags="${var_tags:-email;archive;smtp}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/piler/piler.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "piler" "jsuto/piler"; then
    msg_info "Stopping Piler Services"
    $STD systemctl stop piler
    $STD systemctl stop manticore
    msg_ok "Stopped Piler Services"

    msg_info "Backing up Configuration"
    cp /etc/piler/piler.conf /tmp/piler.conf.bak
    cp /var/www/piler/config-site.php /tmp/config-site.php.bak 2>/dev/null || true
    msg_ok "Backed up Configuration"

    msg_info "Updating ${APP}"
    cd /tmp
    fetch_and_deploy_gh_release "piler" "jsuto/piler" "binary" "latest" "/tmp" "piler_*-noble-*_amd64.deb"
    fetch_and_deploy_gh_release "piler-webui" "jsuto/piler" "binary" "latest" "/tmp" "piler-webui_*-noble-*_amd64.deb"
    $STD apt-get -f install -y
    msg_ok "Updated ${APP}"

    msg_info "Restoring Configuration"
    cp /tmp/piler.conf.bak /etc/piler/piler.conf
    [[ -f /tmp/config-site.php.bak ]] && cp /tmp/config-site.php.bak /var/www/piler/config-site.php
    rm -f /tmp/piler.conf.bak /tmp/config-site.php.bak
    chown piler:piler /etc/piler/piler.conf
    chown -R piler:piler /var/www/piler 2>/dev/null || true
    msg_ok "Restored Configuration"

    msg_info "Starting Services"
    $STD systemctl start manticore
    $STD systemctl start piler
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
