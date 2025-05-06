#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://alpinelinux.org/

APP="Alpine-Traefik"
var_tags="${var_tags:-os;alpine}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-0.5}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.21}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  msg_info "Enabling edge repository"
  echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >>/etc/apk/repositories
  $STD apk update

  msg_info "Running full system upgrade"
  $STD apk upgrade
  msg_ok "System upgraded"

  msg_info "Disabling edge repository"
  sed -i '/@edge/d' /etc/apk/repositories
  $STD apk update
  msg_ok "Disabled edge repository"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
