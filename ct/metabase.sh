#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: C S P Nanda(cspnanda)
# License: MIT
# https://raw.githubusercontent.com/community-scripts/ProxmoxVE/refs/heads/main/LICENSE
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

function header_info {
clear
cat <<"EOF"
                | |      | |
  _ __ ___   ___| |_ __ _| |__   __ _ ___  ___
 | '_ ` _ \ / _ \ __/ _` | '_ \ / _` / __|/ _ \
 | | | | | |  __/ || (_| | |_) | (_| \__ \  __/
 |_| |_| |_|\___|\__\__,_|_.__/ \__,_|___/\___|

EOF
}
header_info
echo -e "Loading..."
APP="metabase"

var_tags="metabase;dashboard;bi;analytics"
var_disk="4"
var_cpu="1"
var_ram="512"
var_os="debian"
var_version="12"
var_unprivileged=1
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /opt/metabase/metabase.jar ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  apt-get update &>/dev/null
  apt-get -y upgrade &>/dev/null
  systemctl stop metabase.service
  METABASE_VERSION=`curl -s https://api.github.com/repos/metabase/metabase/releases/latest|awk -F \" -v RS="," '/tarball_url/ {print $(NF-1)}'|awk -F '/' '{print $NF}'`
  METABASE_DIR=/opt/metabase
  mv -f /opt/metabase/metabase.jar /opt/metabase/metabase.jar.old
  curl https://downloads.metabase.com/$METABASE_VERSION/metabase.jar -o $METABASE_DIR/metabase.jar
  systemctl start metabase.service
  msg_ok "Updated Successfully"
  msg_info "Waiting for metabase to start"
  while ! nc -z localhost 3000; do
    sleep 5 # wait for 5 seconds before check again
  done

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "Access http://${IP}:3000"
