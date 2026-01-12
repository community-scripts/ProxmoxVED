#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.openeuler.org/

# NOTE: openEuler requires privileged container due to PVE limitation
# PVE's post_create_hook expects /etc/redhat-release which openEuler doesn't have
# This causes "unable to create CT - error in setup task PVE::LXC::Setup::post_create_hook"
# Setting var_unprivileged=0 creates privileged container which bypasses this check

APP="openEuler"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-openeuler}"
var_version="${var_version:-25.03}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating OpenEuler LXC"
  $STD dnf -y upgrade
  msg_ok "Updated OpenEuler LXC"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
msg_custom "🚀" "${GN}" "${APP} setup has been successfully initialized!"
