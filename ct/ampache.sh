#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

APP="Ampache"
var_disk="5"
var_cpu="4"
var_ram="2048"
var_os="debian"
var_version="12"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  if [[ ! -d /opt/ampache ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  cd /opt/bookstack
  git config --global --add safe.directory /opt/bookstack >/dev/null 2>&1
  git pull origin release >/dev/null 2>&1
  composer install --no-interaction --no-dev >/dev/null 2>&1
  php artisan migrate --force >/dev/null 2>&1
  php artisan cache:clear
  php artisan config:clear
  php artisan view:clear
  msg_ok "Updated Successfully"
  exit
  msg_error "There is currently no update path available."
}

start
build_container
description

msg_info "Setting Container to Normal Resources"
pct set $CTID -cores 2
msg_ok "Set Container to Normal Resources"

msg_ok "Completed Successfully!\n"
echo -e "${APP} Setup should be reachable by going to the following URL.
         ${BL}http://${IP}/install.php${CL} \n"
