#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ampache/ampache

APP="Ampache"
var_tags="${var_tags:-music}"
var_disk="${var_disk:-5}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
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
  if [[ ! -d /opt/ampache ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "Ampache" "ampache/ampache"; then
    msg_info "Stopping Apache"
    systemctl stop apache2
    msg_ok "Stopped Apache"

    msg_info "Backing up Configuration"
    cp /opt/ampache/config/ampache.cfg.php /tmp/ampache.cfg.php.backup
    cp /opt/ampache/public/rest/.htaccess /tmp/ampache_rest.htaccess.backup
    cp /opt/ampache/public/play/.htaccess /tmp/ampache_play.htaccess.backup
    cp /opt/ampache/public/channel/.htaccess /tmp/ampache_channel.htaccess.backup
    msg_ok "Backed up Configuration"

    msg_info "Backup Ampache Folder"
    rm -rf /opt/ampache_backup
    mv /opt/ampache /opt/ampache_backup
    msg_ok "Backed up Ampache"

    fetch_and_deploy_gh_release "Ampache" "ampache/ampache" "release" "latest" "/opt/ampache" "ampache-*_all_php8.4.zip"

    msg_info "Restoring Configuration"
    cp /tmp/ampache.cfg.php.backup /opt/ampache/config/ampache.cfg.php
    cp /tmp/ampache_rest.htaccess.backup /opt/ampache/public/rest/.htaccess
    cp /tmp/ampache_play.htaccess.backup /opt/ampache/public/play/.htaccess
    cp /tmp/ampache_channel.htaccess.backup /opt/ampache/public/channel/.htaccess
    chmod 664 /opt/ampache/public/rest/.htaccess /opt/ampache/public/play/.htaccess /opt/ampache/public/channel/.htaccess
    chown -R www-data:www-data /opt/ampache
    rm -f /tmp/ampache*.backup
    msg_ok "Restored Configuration"

    msg_info "Starting Apache"
    systemctl start apache2
    msg_ok "Started Apache"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/install.php${CL}"
